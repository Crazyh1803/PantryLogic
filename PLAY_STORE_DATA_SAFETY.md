# Pantry Logic — Google Play Data Safety Worksheet

This worksheet describes Pantry Logic version 1.0.1 based on the current source. Recheck it whenever providers, SDKs, permissions, or data flows change. The final Play Console answers remain the developer's responsibility.

## High-level answers

- **Does the app collect or share required user-data types?** Yes. Under Google Play's definition, optional AI requests transmit user-provided content off the device directly to the configured provider.
- **Is all transmitted user data encrypted in transit?** Yes for the app's supported network calls; they use HTTPS.
- **Can users request deletion?** Pantry Logic has no account or Apps by Dan server copy. Local data is removed with in-app deletion controls where offered, Android “Clear storage,” or uninstall. Provider-held data is controlled through that provider.
- **Account creation:** None.
- **Ads:** No.
- **Analytics or crash-reporting SDKs:** None.

## Data types to consider declaring as collected

All items below are optional and used for app functionality. They are sent only when the user invokes a network or AI feature.

| Play category | Data type | Why it may be transmitted |
|---|---|---|
| Photos and videos | Photos | A recipe screenshot selected for AI extraction. |
| Files and docs | Files and docs | A user-selected recipe image or imported content, depending on Play's classification. Avoid double-counting the same image if classified as Photos. |
| App activity | Other user-generated content | Recipe captions, notes, recipes, ingredients, prompts, household preferences, and planning context sent for AI processing. |
| Personal info | Name | Household-member names may be included in an AI planning or recipe request. |
| Location | Approximate location | A manually entered region or country may be included in AI context. The app does not request device location permission. |
| Personal info | User IDs | A provider API key may identify or authenticate the user's provider account. Confirm the appropriate classification with the provider's current guidance. |

For each declared type, the purpose is **App functionality**. Collection is **optional** because core recipes, local caption parsing, planning, and shopping features can be used without configuring AI.

## Sharing treatment

AI requests go directly to Google, OpenAI, Anthropic, or xAI after the user configures a provider and invokes an AI feature. Google Play's current guidance says a transfer caused by a specific user-initiated action, where sharing is reasonably expected, may be excluded from the Data Safety definition of “sharing.” Confirm this interpretation while completing the live form. Regardless of the checkbox treatment, the privacy policy discloses every provider transfer.

User-initiated Android sharing and printing also transfer selected content to another app or service. The same user-initiated-transfer exception may apply.

## Data that stays on-device

Recipes, grocery lists, meal plans, history, household profiles, preferences, and settings are normally processed locally. Google Play states that data processed only on-device is outside its “collected” definition. API keys use secure storage. The SQLite app database is protected by Android app isolation but is not represented as independently encrypted by Pantry Logic.

## Third parties and links to review

- Google Gemini: https://policies.google.com/privacy
- OpenAI: https://openai.com/policies/privacy-policy/
- Anthropic Claude: https://www.anthropic.com/legal/privacy
- xAI Grok: https://x.ai/legal/privacy-policy
- Linked recipe websites receive normal network request information when the user imports a URL.

## Play Console checklist

1. Host `privacy-policy.html` at a public HTTPS URL that is active, non-geofenced, and not editable by visitors.
2. Enter that URL under **Policy and programs → App content → Privacy policy**.
3. Keep the in-app Privacy Policy entry in Settings.
4. Complete **Data safety** consistently with the policy and current provider behavior.
5. Declare **No** for ads while the app remains ad-free.
6. Select a general-audience target only if that matches the intended audience; the app is not designed for children.
7. Replace the public GitHub issue contact with a dedicated privacy email if available.

