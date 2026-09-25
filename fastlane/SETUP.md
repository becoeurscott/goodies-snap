# Goodies Snap Fastlane Setup

## 1. Create the App Store Connect API key

In App Store Connect, go to Users and Access > Integrations > App Store Connect API.
Create an API key with App Manager or Admin access, download the `.p8` file, and copy it into `fastlane/`.
If the key is limited to specific apps, make sure it has access to Goodies Snap. A key with
read-only or Developer-only permissions can authenticate, but metadata upload will fail with:
`This request is forbidden for security reasons - The API key in use does not allow this request`.

## 2. Add local secrets

Copy the example file:

```sh
cp fastlane/.env.example fastlane/.env
```

Fill in:

- `ASC_KEY_ID`
- `ASC_ISSUER_ID`
- `ASC_KEY_PATH`

`fastlane/.env` and `fastlane/*.p8` are ignored by git.

App Review contact details and the demo login are also local-only (the repository is
public). Create these one-line files in `fastlane/metadata/review_information/`:
`demo_user.txt`, `demo_password.txt`, `first_name.txt`, `last_name.txt`,
`email_address.txt`, `phone_number.txt`. They are ignored by git; `notes.txt` stays tracked.

## 3. Install Fastlane

```sh
export PATH="$HOME/.rbenv/bin:$HOME/.rbenv/shims:$PATH"
bundle config path vendor/bundle
bundle install
```

## 4. Useful lanes

Check metadata:

```sh
export PATH="$HOME/.rbenv/bin:$HOME/.rbenv/shims:$PATH"
bundle exec fastlane ios check_metadata
```

Upload App Store text/review info only:

```sh
export PATH="$HOME/.rbenv/bin:$HOME/.rbenv/shims:$PATH"
bundle exec fastlane ios metadata
```

Build a signed App Store IPA:

```sh
export PATH="$HOME/.rbenv/bin:$HOME/.rbenv/shims:$PATH"
bundle exec fastlane ios build
```

Upload to TestFlight:

```sh
export PATH="$HOME/.rbenv/bin:$HOME/.rbenv/shims:$PATH"
bundle exec fastlane ios beta
```

Upload build plus metadata to App Store Connect without submitting:

```sh
export PATH="$HOME/.rbenv/bin:$HOME/.rbenv/shims:$PATH"
bundle exec fastlane ios release
```

Submit the current App Store version for review:

```sh
export PATH="$HOME/.rbenv/bin:$HOME/.rbenv/shims:$PATH"
CONFIRM_APP_REVIEW_SUBMIT=YES bundle exec fastlane ios submit_review
```

## Do not submit until fixed

- Sign in with Apple must be fully implemented if Google Sign-In remains enabled.
- `https://j7pth4qn.insforge.site/privacy.html` and `/terms.html` must be live.
- App Store Connect subscriptions must be ready and attached to the app version.
- App Privacy answers must match the app's real data collection.
- The AI backend must be live so reviewers can test recipe capture.
