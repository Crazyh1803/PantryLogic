# Pantry Logic Privacy Policy

**Effective date:** September 17, 2026  
**Developer:** Apps by Dan ("AppsbyDan")  
**Application ID:** `com.appsbydan.pantrylogic`

Pantry Logic is a local-first recipe, meal-planning, and grocery-list application. This Privacy Policy explains what information Pantry Logic accesses, where it is stored, when it leaves your device, and the choices available to you.

## Summary

- Pantry Logic does not require an account.
- Apps by Dan does not operate a server that receives your recipes, meal plans, grocery lists, household profiles, or API keys.
- Recipes, meal plans, shopping lists, cooking history, household profiles, and settings are stored locally on your device.
- If you choose an AI-powered feature, information needed for that request is sent directly from your device to the AI provider you configured.
- Pantry Logic does not contain advertising or analytics SDKs and does not sell personal information.

## Information stored on your device

Pantry Logic may store the following information locally:

- recipes, ingredients, instructions, source links, and recipe notes;
- meal plans, grocery lists, cooking history, serving counts, and cooldown preferences;
- household-member names, likes, dislikes, and guest counts;
- region, preferred stores, cooking equipment, measurement choices, and AI recipe preferences;
- AI-provider selections and model names; and
- API keys that you enter.

This information is used to provide the app's recipe, planning, shopping, and personalization features. The application database is stored in Android's private app storage. API keys are stored using the device's secure-storage facilities and are excluded from Pantry Logic backup exports. Android cloud backup is disabled for the app.

## Information sent off your device

### AI features

AI features are optional. When you ask Pantry Logic to extract, compose, replace, or recommend a recipe, the app may send the information needed for that request directly to your selected AI provider. Depending on the feature and the information you supplied, this may include:

- recipe text, captions, notes, ingredients, recipe titles, and source URLs;
- screenshots or other recipe images you selected;
- requested protein, cuisine, dish, or recipe directions;
- household-member names and selected likes or dislikes;
- region, preferred stores, cooking equipment, and other recipe preferences; and
- the API key needed to authenticate the request with that provider.

If you enable provider fallback, the same request may be sent to additional configured providers until one completes it. Pantry Logic currently supports Google Gemini, OpenAI, Anthropic Claude, and xAI Grok. Requests use encrypted HTTPS connections. Each provider processes information under its own terms and privacy policy, and may retain request data according to its account settings and policies:

- [Google Privacy Policy](https://policies.google.com/privacy)
- [OpenAI Privacy Policy](https://openai.com/policies/privacy-policy/)
- [Anthropic Privacy Policy](https://www.anthropic.com/legal/privacy)
- [xAI Privacy Policy](https://x.ai/legal/privacy-policy)

Apps by Dan does not receive or control the data sent directly to these providers. Avoid including sensitive personal information in recipe notes, household profiles, or AI prompts.

### Recipe links

When you import a recipe link, Pantry Logic may connect directly to the linked website to retrieve publicly available recipe text. That website receives ordinary network information such as your IP address and request metadata and handles it under its own privacy policy. If the retrieved text is not sufficient for local parsing, it may be included in an AI request as described above.

### Sharing and printing

When you choose Share or Print, Pantry Logic passes the selected recipe or grocery-list text to Android's share or print service. Information is provided to another app or service only after you initiate that action. The recipient handles the information under its own privacy practices.

### External links

Pantry Logic can open external pages for API-key help, provider documentation, Amazon Alexa help, support, or Apps by Dan. Your browser and the destination website handle those visits under their own privacy practices.

## Backup files

You may export a Pantry Logic backup file. The backup can contain recipes, household profiles, meal plans, shopping data, cooking history, and settings. API keys are excluded. You choose where to save or share the file, and you are responsible for protecting and deleting copies stored outside the app.

## Information Pantry Logic does not collect for Apps by Dan

Pantry Logic does not include advertising, behavioral analytics, crash-reporting, or tracking SDKs. Apps by Dan does not use Pantry Logic to collect precise GPS location, contacts, phone numbers, email addresses, advertising identifiers, payment information, or a list of other apps installed on your device.

## Retention and deletion

Local information remains on your device until you delete it in Pantry Logic where a deletion control is available, clear the app's storage, or uninstall the app. Backup files remain wherever you saved them until you delete them.

Pantry Logic has no Apps by Dan account and Apps by Dan has no Pantry Logic server copy to delete. To request deletion of information held by an AI provider or another third party, use that provider's privacy controls or contact the provider directly.

## Security

Pantry Logic uses Android application isolation for its local database, secure device storage for API keys, and HTTPS for supported network requests. No storage or transmission method is completely secure, so you should protect access to your device, backup files, and provider API keys.

## Children

Pantry Logic is a general-audience household utility and is not directed to children under 13. The app does not knowingly collect children's personal information for Apps by Dan.

## Changes to this policy

This policy may be updated when Pantry Logic's features or data practices change. The effective date above will be revised when a material update is published. The current version should remain available from the app and its public privacy-policy webpage.

## Contact

For privacy questions, open a privacy inquiry through the [Pantry Logic project contact page](https://github.com/Crazyh1803/PantryLogic/issues). Do not include API keys or sensitive personal information in a public issue. A dedicated privacy email may replace this contact mechanism before public release.

