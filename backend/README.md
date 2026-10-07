# PINGGO MongoDB Gateway & Sync Backend

This is the official zero-trust backend API gateway for **PINGGO**, enabling cross-device synchronization between macOS and Windows using **MongoDB**.

---

## 🚀 Quickstart

### Option 1: Run with Docker Compose (Recommended)

Starts MongoDB + PINGGO Gateway automatically:

```bash
cd backend
docker compose up -d
```

The gateway is now listening at `http://localhost:4000`.

---

### Option 2: Run with Local Node.js & MongoDB Atlas

1. Install dependencies:
   ```bash
   cd backend
   npm install
   ```

2. Configure environment:
   ```bash
   cp .env.example .env
   ```
   Edit `.env` and set your MongoDB Atlas connection string:
   ```env
   PORT=4000
   MONGODB_URI=mongodb+srv://<username>:<password>@cluster0.mongodb.net/pinggo?retryWrites=true&w=majority
   JWT_SECRET=your_custom_jwt_secret_key
   ```

3. Start server:
   ```bash
   npm start
   ```

---

## 📱 Connecting PINGGO Desktop App to MongoDB

1. Open **PINGGO** on your Mac or Windows PC.
2. Go to **Settings** (`⌘,`) > **Account**.
3. Under **MongoDB Cloud Sync**:
   - Toggle **Enable MongoDB Sync** to **ON**.
   - Set **Backend API Gateway URL** to `http://localhost:4000` (or your deployed cloud URL e.g. `https://api.yourdomain.com`).
   - Enter your email and password, then click **Connect**.
4. Tap **Sync with MongoDB** to immediately replicate Spaces, preferences, and layouts.

---

## 🛡️ Security & Privacy Guarantee

- **Zero-Trust**: Client credentials, social account cookies, and passwords **never** leave the local device.
- Only non-sensitive sync metadata (space names, layout positions, preference themes, and bookmarks) is replicated to MongoDB.
