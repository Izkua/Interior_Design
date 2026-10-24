# App Privacy answers for App Store Connect (DRAFT checklist)

Based on what the code sends as of October 2026. Re-check after any change, especially when an image model is connected. Apple's form uses its own category names; these are the ones that apply.

## Data used to track you
**None.** No ads, no analytics SDKs, no data brokers, no cross-app tracking. The app doesn't need App Tracking Transparency.

## Data linked to you (only if the person creates an account)

| Apple category | What | Purpose |
| --- | --- | --- |
| Contact Info → Email Address | Account email | App Functionality |
| Contact Info → Name | From Google/Apple sign-in, if shared | App Functionality |
| User Content → Other User Content | Shopping preferences and budget | App Functionality |
| Usage Data → Product Interaction | AI picture count (for limits) | App Functionality |
| User Content → Photos or Videos | Optional room photo sent for an AI picture, **only once Visualize is switched on** | App Functionality |
| Identifiers → User ID | Account ID, used for rate limits | App Functionality |

## Data not linked to you

| Apple category | What | Purpose |
| --- | --- | --- |
| Identifiers → Device ID | Random per-install ID sent with catalog searches (not the advertising ID) | App Functionality (rate limiting) |
| Search History | Catalog search words and filters | App Functionality |

## Not collected
Location, contacts, health, financial info, browsing history, sensitive info, purchases (no in-app purchases in v1), and diagnostics (unless you add a crash-reporting tool later).

## Points to double-check before submitting
- Furniture photos and room data stay on the device, so they aren't "collected". Confirm `BackendConfig.backendLabelingEnabled` and `roomScanEnabled` are still `false`.
- Turning on Visualize starts sending room photos to the backend and the image provider. Update this form and the privacy policy at the same time.
- Retailer pages open in Safari View Controller; the retailer's data collection isn't yours to declare.
