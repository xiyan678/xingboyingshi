# Android release signing

Release signing is read only from environment variables. The keystore and its
passwords must never be committed to Git or uploaded with source archives.

Required variables:

- `XINGBO_KEYSTORE`: absolute path to the `.jks` file
- `XINGBO_STORE_PASSWORD`: keystore password
- `XINGBO_KEY_ALIAS`: key alias (`xingbo` for the owner's current key)
- `XINGBO_KEY_PASSWORD`: private-key password

Without all four variables, release APKs are left unsigned. Debug builds keep
using Android's standard debug certificate.

Back up the keystore in at least two private locations. All future Android
updates for package `pro.xbxx.xingbo_app` must use this same key. Losing it, or
changing the application ID, prevents an update from installing over the
existing release app.
