const path = require('path');
const fs = require('fs');

// Auto-load .env from backend directory or project root
const backendEnv = path.join(__dirname, '.env');
const rootEnv = path.join(__dirname, '..', '.env');
const atlasEnv = path.join(__dirname, 'atlas-credentials.env');
const rootAtlasEnv = path.join(__dirname, '..', 'atlas-credentials.env');

if (fs.existsSync(backendEnv)) {
    require('dotenv').config({ path: backendEnv });
} else if (fs.existsSync(rootEnv)) {
    require('dotenv').config({ path: rootEnv });
} else {
    require('dotenv').config();
}

if (fs.existsSync(atlasEnv)) {
    require('dotenv').config({ path: atlasEnv });
} else if (fs.existsSync(rootAtlasEnv)) {
    require('dotenv').config({ path: rootAtlasEnv });
}

const http = require('http');
const express = require('express');
const cors = require('cors');
const { MongoClient, ObjectId } = require('mongodb');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const { WebSocketServer } = require('ws');

const app = express();
const server = http.createServer(app);
const PORT = process.env.PORT || 4000;
const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/pinggo';
const DB_NAME = process.env.MONGODB_DB_NAME || 'pinggo';
const JWT_SECRET = process.env.JWT_SECRET || 'pinggo_jwt_secret_development_key_9841';

app.use(cors());
app.use(express.json({ limit: '10mb' }));

let db = null;
let dbMode = 'connecting'; // 'atlas' | 'local_fallback'
let usersCol, spacesCol, prefsCol, briefingsCol, bookmarksCol;

// Local Embedded JSON Storage Engine
const DATA_DIR = path.join(__dirname, 'data');
const LOCAL_DB_FILE = path.join(DATA_DIR, 'pinggo_local_db.json');

if (!fs.existsSync(DATA_DIR)) {
    try { fs.mkdirSync(DATA_DIR, { recursive: true }); } catch (e) {}
}

let localData = {
    users: [],
    spaces: [],
    preferences: [],
    ai_briefings: [],
    browser_bookmarks: []
};

try {
    if (fs.existsSync(LOCAL_DB_FILE)) {
        localData = JSON.parse(fs.readFileSync(LOCAL_DB_FILE, 'utf8'));
    }
} catch (e) {
    console.warn('[LocalDB] Initializing fresh local storage.');
}

function saveLocalDB() {
    try {
        fs.writeFileSync(LOCAL_DB_FILE, JSON.stringify(localData, null, 2), 'utf8');
    } catch (e) {
        console.error('[LocalDB] Write error:', e.message);
    }
}

function matchesFilter(doc, filter) {
    if (!filter || Object.keys(filter).length === 0) return true;
    for (const [key, val] of Object.entries(filter)) {
        if (key === '_id') {
            if (String(doc._id) !== String(val)) return false;
            continue;
        }
        if (val && typeof val === 'object' && val.$gte !== undefined) {
            const docVal = doc[key] ? new Date(doc[key]) : new Date(0);
            if (docVal < new Date(val.$gte)) return false;
            continue;
        }
        if (doc[key] !== val) return false;
    }
    return true;
}

class LocalCollection {
    constructor(name) {
        this.name = name;
        if (!localData[name]) localData[name] = [];
        this.docs = localData[name];
    }
    async createIndex() { return true; }
    async findOne(filter, options = {}) {
        const match = this.docs.find(d => matchesFilter(d, filter));
        if (!match) return null;
        const copy = JSON.parse(JSON.stringify(match));
        if (options?.projection) {
            for (const [k, v] of Object.entries(options.projection)) {
                if (v === 0) delete copy[k];
            }
        }
        return copy;
    }
    find(filter = {}) {
        let matched = this.docs.filter(d => matchesFilter(d, filter));
        return {
            sort: () => ({
                limit: (lim) => ({
                    toArray: async () => JSON.parse(JSON.stringify(matched.slice(0, lim)))
                }),
                toArray: async () => JSON.parse(JSON.stringify(matched))
            }),
            limit: (lim) => ({
                toArray: async () => JSON.parse(JSON.stringify(matched.slice(0, lim)))
            }),
            toArray: async () => JSON.parse(JSON.stringify(matched))
        };
    }
    async insertOne(doc) {
        const _id = doc._id || new ObjectId().toString();
        const copy = { ...doc, _id };
        this.docs.push(copy);
        saveLocalDB();
        return { insertedId: _id };
    }
    async updateOne(filter, update, options = {}) {
        const idx = this.docs.findIndex(d => matchesFilter(d, filter));
        if (idx >= 0) {
            if (update.$set) Object.assign(this.docs[idx], update.$set);
            if (update.$addToSet) {
                for (const [k, v] of Object.entries(update.$addToSet)) {
                    if (!Array.isArray(this.docs[idx][k])) this.docs[idx][k] = [];
                    this.docs[idx][k].push(v);
                }
            }
            saveLocalDB();
            return { matchedCount: 1, modifiedCount: 1 };
        } else if (options?.upsert) {
            const newDoc = { ...filter, ...(update.$set || {}), _id: new ObjectId().toString() };
            this.docs.push(newDoc);
            saveLocalDB();
            return { matchedCount: 0, upsertedCount: 1, upsertedId: newDoc._id };
        }
        return { matchedCount: 0, modifiedCount: 0 };
    }
    async deleteMany(filter) {
        const before = this.docs.length;
        const remaining = this.docs.filter(d => !matchesFilter(d, filter));
        localData[this.name] = remaining;
        this.docs = remaining;
        saveLocalDB();
        return { deletedCount: before - remaining.length };
    }
}

function initLocalFallback() {
    dbMode = 'local_fallback';
    usersCol = new LocalCollection('users');
    spacesCol = new LocalCollection('spaces');
    prefsCol = new LocalCollection('preferences');
    briefingsCol = new LocalCollection('ai_briefings');
    bookmarksCol = new LocalCollection('browser_bookmarks');
    console.log('[Database] Operating in Local Fallback mode (persistent store: backend/data/pinggo_local_db.json)');
    console.log('[Database] All desktop sync and auth features are active.');
}

// MongoDB Connection with Auto-Fallback
async function connectDB() {
    const host = MONGODB_URI.includes('@') ? MONGODB_URI.split('@')[1].split('/')[0] : 'localhost';
    console.log(`[MongoDB] Attempting connection to Atlas cluster: ${host}...`);

    try {
        const client = new MongoClient(MONGODB_URI, {
            serverSelectionTimeoutMS: 8000,
        });
        await client.connect();
        db = client.db(DB_NAME);
        dbMode = 'atlas';
        usersCol = db.collection('users');
        spacesCol = db.collection('spaces');
        prefsCol = db.collection('preferences');
        briefingsCol = db.collection('ai_briefings');
        bookmarksCol = db.collection('browser_bookmarks');

        await usersCol.createIndex({ email: 1 }, { unique: true });
        await spacesCol.createIndex({ userId: 1 });
        await prefsCol.createIndex({ userId: 1 }, { unique: true });
        await briefingsCol.createIndex({ userId: 1, dateString: 1 });
        await bookmarksCol.createIndex({ userId: 1 });
        console.log(`[MongoDB] Connected directly to MongoDB Atlas (${db.databaseName})!`);
    } catch (err) {
        console.warn(`[MongoDB] Atlas connection pending (${err.message})`);
        console.warn('[MongoDB] TIP: Whitelist your IP in MongoDB Atlas -> Network Access.');
        if (dbMode !== 'atlas') {
            initLocalFallback();
        }
        // Auto-retry Atlas connection in background every 45s
        setTimeout(connectDB, 45000);
    }
}

// Database Ready Check Middleware
function requireDB(req, res, next) {
    if (!usersCol) {
        return res.status(503).json({
            error: 'Database initializing. Please retry in a few seconds.'
        });
    }
    next();
}

// Authentication Middleware
function authenticateToken(req, res, next) {
    const authHeader = req.headers['authorization'];
    const token = authHeader && authHeader.split(' ')[1];
    if (!token) return res.status(401).json({ error: 'Access token required' });

    jwt.verify(token, JWT_SECRET, (err, user) => {
        if (err) return res.status(403).json({ error: 'Invalid or expired token' });
        req.user = user;
        next();
    });
}

// Apply requireDB to all API routes
app.use('/api', requireDB);

// MARK: - Health Check
app.get('/health', (req, res) => {
    res.json({
        status: 'ok',
        service: 'pinggo-mongodb-gateway',
        databaseConnected: Boolean(usersCol),
        databaseMode: dbMode,
        clusterHost: MONGODB_URI.includes('@') ? MONGODB_URI.split('@')[1].split('/')[0] : 'localhost',
        timestamp: new Date().toISOString()
    });
});

// MARK: - Subscription Helpers
function evaluateUserTier(user) {
    if (!user) return { user, modified: false };
    let modified = false;

    if (user.tier === 'pro') {
        if (user.tierExpiresAt) {
            const expiry = new Date(user.tierExpiresAt);
            if (expiry.getTime() <= Date.now()) {
                // Tier has expired! Automatically downgrade to 'free'
                console.log(`[Subscription] User ${user.email} Pro tier expired at ${expiry.toISOString()}. Automatically downgrading to free.`);
                user.tier = 'free';
                user.subscriptionStatus = 'expired';
                user.previousTier = 'pro';
                user.expiredAt = expiry;
                modified = true;
            } else {
                user.subscriptionStatus = 'active';
            }
        } else {
            // Pro with no expiry treated as active
            user.subscriptionStatus = 'active';
        }
    } else {
        if (!user.subscriptionStatus || user.subscriptionStatus !== 'expired') {
            user.subscriptionStatus = 'free';
        }
    }
    return { user, modified };
}

function calculateSubscriptionMeta(user) {
    const expiresAt = user.tierExpiresAt ? new Date(user.tierExpiresAt) : null;
    const now = Date.now();
    let daysRemaining = 0;
    let isExpired = false;

    if (expiresAt) {
        const diffMs = expiresAt.getTime() - now;
        daysRemaining = Math.max(0, Math.ceil(diffMs / (1000 * 60 * 60 * 24)));
        isExpired = diffMs <= 0;
    } else if (user.subscriptionStatus === 'expired') {
        isExpired = true;
    }

    const needsRenewal = isExpired || (user.tier === 'pro' && daysRemaining <= 5);

    return {
        tier: user.tier || 'free',
        subscriptionStatus: user.subscriptionStatus || 'free',
        tierExpiresAt: user.tierExpiresAt ? new Date(user.tierExpiresAt).toISOString() : null,
        daysRemaining,
        isExpired,
        needsRenewal,
        planName: user.planName || (user.tier === 'pro' ? 'PINGGO Pro' : 'PINGGO Free')
    };
}

// MARK: - Authentication Routes
app.post('/api/v1/auth/register', async (req, res) => {
    try {
        const { email, password, displayName, deviceId, platform } = req.body;
        if (!email || !password) {
            return res.status(400).json({ error: 'Email and password required' });
        }

        const cleanEmail = email.trim().toLowerCase();
        const existing = await usersCol.findOne({ email: cleanEmail });
        if (existing) {
            return res.status(409).json({ error: 'User already exists' });
        }

        const hashedPassword = await bcrypt.hash(password, 10);
        const newUser = {
            email: cleanEmail,
            password: hashedPassword,
            displayName: displayName || cleanEmail.split('@')[0],
            tier: 'free',
            tierExpiresAt: null,
            subscriptionStatus: 'free',
            planName: 'PINGGO Free',
            devices: deviceId ? [{ deviceId, platform: platform || 'macOS', lastActiveAt: new Date() }] : [],
            createdAt: new Date(),
            updatedAt: new Date()
        };

        const result = await usersCol.insertOne(newUser);
        const token = jwt.sign({ id: result.insertedId.toString(), email: cleanEmail }, JWT_SECRET, { expiresIn: '60d' });
        const subMeta = calculateSubscriptionMeta(newUser);

        res.status(201).json({
            token,
            user: {
                id: result.insertedId.toString(),
                email: cleanEmail,
                displayName: newUser.displayName,
                ...subMeta
            }
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.post('/api/v1/auth/login', async (req, res) => {
    try {
        const { email, password, deviceId, platform } = req.body;
        if (!email || !password) {
            return res.status(400).json({ error: 'Email and password required' });
        }

        const cleanEmail = email.trim().toLowerCase();
        const user = await usersCol.findOne({ email: cleanEmail });
        if (!user) {
            return res.status(401).json({ error: 'Invalid email or password' });
        }

        const isMatch = await bcrypt.compare(password, user.password);
        if (!isMatch) {
            return res.status(401).json({ error: 'Invalid email or password' });
        }

        // Auto-evaluate subscription validity on login
        const { user: evaluatedUser, modified } = evaluateUserTier(user);
        if (modified) {
            await usersCol.updateOne(
                { _id: user._id },
                {
                    $set: {
                        tier: evaluatedUser.tier,
                        subscriptionStatus: evaluatedUser.subscriptionStatus,
                        previousTier: evaluatedUser.previousTier,
                        expiredAt: evaluatedUser.expiredAt,
                        updatedAt: new Date()
                    }
                }
            );
        }

        // Update device activity
        if (deviceId) {
            await usersCol.updateOne(
                { _id: user._id },
                {
                    $set: { updatedAt: new Date() },
                    $addToSet: { devices: { deviceId, platform: platform || 'macOS', lastActiveAt: new Date() } }
                }
            );
        }

        const token = jwt.sign({ id: user._id.toString(), email: cleanEmail }, JWT_SECRET, { expiresIn: '60d' });
        const subMeta = calculateSubscriptionMeta(evaluatedUser);

        res.json({
            token,
            user: {
                id: user._id.toString(),
                email: cleanEmail,
                displayName: evaluatedUser.displayName,
                ...subMeta
            }
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// MARK: - Subscription Management Routes
app.get('/api/v1/subscription/status', authenticateToken, async (req, res) => {
    try {
        const userId = req.user.id;
        let user = null;
        try { user = await usersCol.findOne({ _id: new ObjectId(userId) }); } catch (e) {}
        if (!user) user = await usersCol.findOne({ _id: userId });
        if (!user) return res.status(404).json({ error: 'User not found' });

        const { user: evaluatedUser, modified } = evaluateUserTier(user);
        if (modified) {
            await usersCol.updateOne(
                { _id: user._id },
                {
                    $set: {
                        tier: evaluatedUser.tier,
                        subscriptionStatus: evaluatedUser.subscriptionStatus,
                        previousTier: evaluatedUser.previousTier,
                        expiredAt: evaluatedUser.expiredAt,
                        updatedAt: new Date()
                    }
                }
            );
        }

        const subMeta = calculateSubscriptionMeta(evaluatedUser);
        res.json({
            ...subMeta,
            canRenew: true
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.post('/api/v1/subscription/upgrade', authenticateToken, async (req, res) => {
    try {
        const userId = req.user.id;
        const { plan, durationDays, paymentMethod } = req.body;
        let days = (durationDays !== undefined && !isNaN(parseInt(durationDays)))
            ? parseInt(durationDays)
            : (plan === 'annual' ? 365 : 30);

        let user = null;
        try { user = await usersCol.findOne({ _id: new ObjectId(userId) }); } catch (e) {}
        if (!user) user = await usersCol.findOne({ _id: userId });
        if (!user) return res.status(404).json({ error: 'User not found' });

        // If currently active Pro and adding positive days, extend from current expiry; otherwise extend from now
        let baseDate = Date.now();
        if (days > 0 && user.tier === 'pro' && user.tierExpiresAt && new Date(user.tierExpiresAt).getTime() > Date.now()) {
            baseDate = new Date(user.tierExpiresAt).getTime();
        }

        const newExpiresAt = new Date(baseDate + days * 24 * 60 * 60 * 1000);
        const planName = plan === 'annual' ? 'PINGGO Pro (Annual)' : 'PINGGO Pro (Monthly)';

        await usersCol.updateOne(
            { _id: user._id },
            {
                $set: {
                    tier: 'pro',
                    tierExpiresAt: newExpiresAt,
                    subscriptionStatus: 'active',
                    planName,
                    lastPaymentAt: new Date(),
                    lastPaymentMethod: paymentMethod || 'In-App Payment / Card',
                    updatedAt: new Date()
                }
            }
        );

        user.tier = 'pro';
        user.tierExpiresAt = newExpiresAt;
        user.subscriptionStatus = 'active';
        user.planName = planName;

        const subMeta = calculateSubscriptionMeta(user);

        // Real-time broadcast to all client windows/devices
        broadcastToUser(userId, {
            type: 'SUBSCRIPTION_UPDATED',
            ...subMeta,
            message: `Upgraded to ${planName}. Valid until ${newExpiresAt.toLocaleDateString()}`
        });

        res.json({
            success: true,
            message: `Successfully activated ${planName}!`,
            ...subMeta
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.post('/api/v1/subscription/renew', authenticateToken, async (req, res) => {
    try {
        const userId = req.user.id;
        const { plan, durationDays, paymentMethod } = req.body;
        let days = parseInt(durationDays) || (plan === 'annual' ? 365 : 30);

        let user = null;
        try { user = await usersCol.findOne({ _id: new ObjectId(userId) }); } catch (e) {}
        if (!user) user = await usersCol.findOne({ _id: userId });
        if (!user) return res.status(404).json({ error: 'User not found' });

        let baseDate = Date.now();
        if (user.tierExpiresAt && new Date(user.tierExpiresAt).getTime() > Date.now()) {
            baseDate = new Date(user.tierExpiresAt).getTime();
        }

        const newExpiresAt = new Date(baseDate + days * 24 * 60 * 60 * 1000);
        const planName = plan === 'annual' ? 'PINGGO Pro (Annual)' : 'PINGGO Pro (Monthly)';

        await usersCol.updateOne(
            { _id: user._id },
            {
                $set: {
                    tier: 'pro',
                    tierExpiresAt: newExpiresAt,
                    subscriptionStatus: 'active',
                    planName,
                    lastPaymentAt: new Date(),
                    lastPaymentMethod: paymentMethod || 'Repayment / Card',
                    updatedAt: new Date()
                }
            }
        );

        user.tier = 'pro';
        user.tierExpiresAt = newExpiresAt;
        user.subscriptionStatus = 'active';
        user.planName = planName;

        const subMeta = calculateSubscriptionMeta(user);

        broadcastToUser(userId, {
            type: 'SUBSCRIPTION_UPDATED',
            ...subMeta,
            message: `Plan renewed successfully! Valid until ${newExpiresAt.toLocaleDateString()}`
        });

        res.json({
            success: true,
            message: `Plan renewed successfully!`,
            ...subMeta
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.post('/api/v1/subscription/expire-now', authenticateToken, async (req, res) => {
    try {
        const userId = req.user.id;
        let user = null;
        try { user = await usersCol.findOne({ _id: new ObjectId(userId) }); } catch (e) {}
        if (!user) user = await usersCol.findOne({ _id: userId });
        if (!user) return res.status(404).json({ error: 'User not found' });

        const pastDate = new Date(Date.now() - 3600000);
        user.tier = 'free';
        user.tierExpiresAt = pastDate;
        user.subscriptionStatus = 'expired';
        user.previousTier = 'pro';
        user.expiredAt = pastDate;

        await usersCol.updateOne(
            { _id: user._id },
            {
                $set: {
                    tier: 'free',
                    tierExpiresAt: pastDate,
                    subscriptionStatus: 'expired',
                    previousTier: 'pro',
                    expiredAt: pastDate,
                    updatedAt: new Date()
                }
            }
        );

        const subMeta = calculateSubscriptionMeta(user);
        broadcastToUser(userId, {
            type: 'SUBSCRIPTION_UPDATED',
            ...subMeta,
            message: 'Your PINGGO Pro subscription has expired. Switched to Free tier.'
        });

        res.json({
            success: true,
            message: 'Subscription marked as expired. Account switched to Free tier.',
            ...subMeta
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// MARK: - Sync Routes (Delta Push & Pull)
app.post('/api/v1/sync/push', authenticateToken, async (req, res) => {
    try {
        const userId = req.user.id;
        const { spaces, preferences, bookmarks, briefings } = req.body;

        // 1. Upsert Spaces
        if (Array.isArray(spaces)) {
            for (const space of spaces) {
                await spacesCol.updateOne(
                    { userId, id: space.id },
                    { $set: { ...space, userId, updatedAt: new Date() } },
                    { upsert: true }
                );
            }
        }

        // 2. Upsert Preferences
        if (preferences) {
            await prefsCol.updateOne(
                { userId },
                { $set: { ...preferences, userId, updatedAt: new Date() } },
                { upsert: true }
            );
        }

        // 3. Upsert Bookmarks
        if (Array.isArray(bookmarks)) {
            for (const bm of bookmarks) {
                await bookmarksCol.updateOne(
                    { userId, url: bm.url },
                    { $set: { ...bm, userId, updatedAt: new Date() } },
                    { upsert: true }
                );
            }
        }

        // 4. Return Latest State for Confirmation
        const remoteSpaces = await spacesCol.find({ userId }).toArray();
        res.json({
            success: true,
            syncedAt: new Date().toISOString(),
            spaces: remoteSpaces
        });

        // 5. Broadcast real-time delta notification to other connected devices
        broadcastToUser(userId, {
            type: 'SYNC_UPDATE',
            userId,
            deviceId: req.body?.deviceId,
            timestamp: new Date().toISOString()
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.get('/api/v1/sync/pull', authenticateToken, async (req, res) => {
    try {
        const userId = req.user.id;
        const since = req.query.since ? new Date(req.query.since) : new Date(0);

        const spaces = await spacesCol.find({ userId, updatedAt: { $gte: since } }).toArray();
        const preferences = await prefsCol.findOne({ userId }, { projection: { _id: 0, userId: 0 } });
        const bookmarks = await bookmarksCol.find({ userId, updatedAt: { $gte: since } }).toArray();
        const briefings = await briefingsCol.find({ userId }).sort({ createdAt: -1 }).limit(10).toArray();

        res.json({
            spaces,
            preferences: preferences || null,
            bookmarks,
            briefings,
            pulledAt: new Date().toISOString()
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// MARK: - WebSocket Real-Time Synchronization Server
const wss = new WebSocketServer({ server, path: '/ws' });
const userSockets = new Map(); // userId -> Set<WebSocket>

function broadcastToUser(userId, data, excludeWs = null) {
    const sockets = userSockets.get(userId);
    if (!sockets) return;
    const payload = JSON.stringify(data);
    for (const ws of sockets) {
        if (ws !== excludeWs && ws.readyState === ws.OPEN) {
            ws.send(payload);
        }
    }
}

wss.on('connection', (ws, req) => {
    try {
        const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
        const token = url.searchParams.get('token');
        if (!token) {
            ws.close(4001, 'Token required');
            return;
        }

        jwt.verify(token, JWT_SECRET, (err, user) => {
            if (err || !user) {
                ws.close(4003, 'Invalid token');
                return;
            }

            ws.userId = user.id;
            if (!userSockets.has(user.id)) {
                userSockets.set(user.id, new Set());
            }
            userSockets.get(user.id).add(ws);
            console.log(`[WebSocket] Live client connected for user ${user.id} (${userSockets.get(user.id).size} active)`);

            ws.send(JSON.stringify({ type: 'CONNECTED', timestamp: new Date().toISOString() }));

            ws.on('close', () => {
                const set = userSockets.get(ws.userId);
                if (set) {
                    set.delete(ws);
                    if (set.size === 0) userSockets.delete(ws.userId);
                }
                console.log(`[WebSocket] Live client disconnected for user ${ws.userId}`);
            });

            ws.on('error', (e) => {
                console.error(`[WebSocket] Error: ${e.message}`);
            });
        });
    } catch (e) {
        ws.close(4000, e.message);
    }
});

// MARK: - Start Server
server.listen(PORT, () => {
    console.log(`[PINGGO API Gateway] HTTP & WebSocket running on http://localhost:${PORT}`);
    connectDB();
});
