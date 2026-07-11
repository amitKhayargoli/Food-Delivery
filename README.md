<div align="center">

# 🛵 Dailo — Food Delivery

**Order. Track. Enjoy.** A complete food delivery platform with a Flutter mobile app, a real-time dispatch engine, and an admin dashboard — all wrapped in a slick, modern UI.

<img src="app/assets/img/deliveryguy.png" alt="Dailo Rider" width="220" />

</div>

---

## 📸 Sneak Peek

| Restaurant & Offers | Food Details | Delivery Experience |
|:---:|:---:|:---:|
| <img src="app/assets/img/Pizza%20Point.png" alt="Restaurant menu with offers" width="240" /> | <img src="app/assets/img/Food%20Details.png" alt="Food details with size selection" width="240" /> | <img src="app/assets/img/deliveryguy.png" alt="Rider on the way" width="240" /> |
| Browse restaurants, bestsellers, and live offers like *Flat 50% OFF*. | Pick your size, customize add-ons, and add to cart in one tap. | Real-time rider tracking from pickup to your doorstep. |

---

## ✨ Features

### 🍕 For Customers
- 🔍 **Smart search** across restaurants, cuisines, and menu items
- 🌤️ **Time-of-day recommendations** — breakfast, lunch, dinner, and late-night picks
- 🛒 **Cart & checkout** with sizes, add-ons, and delivery notes
- ⭐ **Ratings & reviews** with photo uploads
- ❤️ **Favorites** to reorder in a tap
- 📍 **Live order tracking** with rider location & ETA
- 💳 **Multiple payment methods** (Cash on Delivery, eSewa, Khalti, Cards)
- 🎟️ **Coupons & promotions** with automatic discount application
- 💬 **In-app support chat** and problem/refund resolution
- 🔔 **Push notifications** for every order milestone

### 👨‍🍳 For Restaurant Owners
- 🏪 **Restaurant profile & menu management**
- 📈 **Live dashboard** with real-time order updates
- ✅ **Accept / reject orders** with prep-time estimates
- 📊 **Reports & reviews** at a glance

### 🛵 For Riders
- 🚦 **Go online / offline** toggle with live location sharing
- 📦 **Job queue** with pickup & delivery photo proof
- 🗺️ **Navigation** and real-time ETA routing
- ⭐ **Ratings** for delivery experience

### 🛠️ For Admins
- 👥 **Multi-role user management** (user / owner / rider / admin)
- 🍽️ **Restaurant approvals** and application review
- 🛡️ **Dispatch oversight** and problem resolution

---

## 🧱 Tech Stack

| Layer | Technology |
|:---|:---|
| 📱 **Mobile App** | Flutter (Dart) — Provider & Riverpod state management |
| ⚙️ **Backend** | Node.js + TypeScript, Express REST API |
| 🗄️ **Database** | Supabase (PostgreSQL) with realtime subscriptions |
| 🔐 **Auth** | Phone OTP, Email/Password, Google Sign-In, JWT |
| 📣 **Push Notifications** | Firebase Cloud Messaging (FCM) |
| 💻 **Admin Panel** | Next.js (React) + TypeScript |
| 🗺️ **Maps & Routing** | Baato Maps + ETA service |

---

## 🗂️ Project Structure

```
Food-Delivery/
├── app/                    # Flutter mobile application
│   ├── lib/
│   │   ├── core/           # Services, utils, theme
│   │   ├── features/       # Feature modules (auth, data models, etc.)
│   │   ├── models/         # Data models (Order, Food, Restaurant…)
│   │   ├── providers/      # State management (Auth, Cart, Favorites…)
│   │   ├── screens/        # UI screens (user / owner / rider / admin)
│   │   └── widgets/        # Reusable UI components
│   ├── assets/             # Fonts, images, animations
│   └── test/               # Unit & widget tests
├── backend/                # Node.js + TypeScript API
│   ├── src/
│   │   ├── controllers/    # Route handlers
│   │   ├── routes/         # API route definitions
│   │   ├── services/       # Business logic (FCM, rider cleanup…)
│   │   └── db/             # Supabase client
│   └── scripts/            # DB setup & seed scripts
├── frontend/               # Next.js admin dashboard
└── README.md               # You are here ✨
```

---

## 🚀 Getting Started

### Prerequisites
- [Flutter](https://docs.flutter.dev/get-started/install) 3.x
- [Node.js](https://nodejs.org/) 18+
- A [Supabase](https://supabase.com/) project
- A [Firebase](https://firebase.google.com/) project (for FCM)

### 1. Backend

```bash
cd backend
npm install
npm run dev
```

### 2. Mobile App

```bash
cd app
flutter pub get
cp env/dev.example.json env/dev.json   # fill in your Supabase / Firebase keys
flutter run
```

### 3. Admin Dashboard

```bash
cd frontend
npm install
npm run dev
```

### 🔑 Environment Variables

The app reads its config from Dart `--dart-define` values:

| Variable | Description |
|:---|:---|
| `SUPABASE_URL` | Supabase project URL |
| `SUPABASE_ANON_KEY` | Supabase anonymous key |
| `GOOGLE_WEB_CLIENT_ID` | OAuth web client ID for Google Sign-In |

---

## 🧪 Testing

```bash
cd app && flutter test          # Flutter unit & widget tests
cd backend && npm test          # API tests
```

---

## 📄 License

© Dailo Food Delivery. All rights reserved.

<div align="center">

*Made with ❤️ and a whole lot of pizza.* 🍕

</div>
