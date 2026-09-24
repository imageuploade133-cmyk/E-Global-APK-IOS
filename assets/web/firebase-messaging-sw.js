importScripts("https://www.gstatic.com/firebasejs/10.13.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.13.0/firebase-messaging-compat.js");

const firebaseConfig = {
  apiKey: "AIzaSyCuolap_m6yXWEo2csYMyGhEshsHnd1aEQ",
  authDomain: "e-tech-global-hub.firebaseapp.com",
  projectId: "e-tech-global-hub",
  storageBucket: "e-tech-global-hub.firebasestorage.app",
  messagingSenderId: "228699271017",
  appId: "1:228699271017:web:97043359d72b08e99917f8",
};

firebase.initializeApp(firebaseConfig);

const messaging = firebase.messaging();

// Handle background messages
messaging.onBackgroundMessage((payload) => {
  console.log("[firebase-messaging-sw.js] Background message received: ", payload);

  const notificationTitle = payload.notification?.title || payload.data?.title || "E-Tech Notification";
  const notificationOptions = {
    body: payload.notification?.body || payload.data?.body || "You have a new transaction or security update.",
    icon: "https://i.ibb.co/WWjZrtC7/E-Tech.png",
    badge: "https://i.ibb.co/WWjZrtC7/E-Tech.png",
    data: payload.data || {},
  };

  self.registration.showNotification(notificationTitle, notificationOptions);
});

// Handle background notification clicks and routing securely
self.addEventListener("notificationclick", (event) => {
  console.log("[Service Worker] Notification clicked:", event);
  event.notification.close();

  const data = event.notification.data || {};
  const rawTxRef = data.reference || data.transactionReference || data.txRef || "";
  const rawUrl = data.url || data.click_action || "/";

  const appOrigin = self.location.origin;
  let destinationUrl = appOrigin + "/";

  // Validate transaction reference format if provided
  if (typeof rawTxRef === "string" && rawTxRef.trim() && /^[A-Za-z0-9_\-]+$/.test(rawTxRef.trim())) {
    const cleanRef = rawTxRef.trim();
    const safeUrl = new URL("/", appOrigin);
    safeUrl.searchParams.set("txRef", cleanRef);
    destinationUrl = safeUrl.toString();
  } else {
    // Validate rawUrl origin and path strictly using URL parsing
    try {
      const parsed = new URL(rawUrl, appOrigin);
      if (parsed.origin === appOrigin && (parsed.pathname === "/" || parsed.pathname === "")) {
        const txParam = parsed.searchParams.get("txRef") || parsed.searchParams.get("transactionReference") || parsed.searchParams.get("reference");
        if (txParam && /^[A-Za-z0-9_\-]+$/.test(txParam)) {
          const safeUrl = new URL("/", appOrigin);
          safeUrl.searchParams.set("txRef", txParam);
          destinationUrl = safeUrl.toString();
        } else {
          destinationUrl = appOrigin + "/";
        }
      }
    } catch {
      destinationUrl = appOrigin + "/";
    }
  }

  event.waitUntil(
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((windowClients) => {
      // Find existing window matching exact origin
      for (let i = 0; i < windowClients.length; i++) {
        const client = windowClients[i];
        try {
          const clientUrl = new URL(client.url);
          if (clientUrl.origin === appOrigin && "focus" in client) {
            return client.navigate(destinationUrl).then((navigatedClient) => navigatedClient.focus());
          }
        } catch {
          // Ignore invalid window client URLs
        }
      }
      if (self.clients.openWindow) {
        return self.clients.openWindow(destinationUrl);
      }
    })
  );
});
