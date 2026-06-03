import { initializeApp } from 'firebase/app';
import { getAuth } from 'firebase/auth';

const firebaseConfig = {
  apiKey:     import.meta.env.VITE_FIREBASE_API_KEY     || '',
  authDomain: import.meta.env.VITE_FIREBASE_AUTH_DOMAIN || '',
  projectId:  import.meta.env.VITE_FIREBASE_PROJECT_ID  || '',
  appId:      import.meta.env.VITE_FIREBASE_APP_ID      || '',
};

export function getFirebaseConfigError() {
  const required = ['apiKey', 'authDomain', 'projectId', 'appId'];
  const missing = required.filter(k => !firebaseConfig[k]);
  if (missing.length === 0) return null;
  return (
    `Missing Firebase configuration: ${missing.join(', ')}. ` +
    'Copy .env.example to .env and fill in the correct values.'
  );
}

const app = initializeApp(firebaseConfig);
export const auth = getAuth(app);
