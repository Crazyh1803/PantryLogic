const privacyPolicyEffectiveDate = 'September 17, 2026';

const privacyPolicyText = '''
Pantry Logic is a local-first recipe, meal-planning, and grocery-list app developed by Apps by Dan.

WHAT STAYS ON YOUR DEVICE
Recipes, ingredients, meal plans, grocery lists, cooking history, household profiles, region, stores, equipment, measurement choices, and settings are stored in Android's private app storage. API keys use secure device storage and are excluded from exported backups. Android cloud backup is disabled.

OPTIONAL AI FEATURES
When you ask Pantry Logic to extract, compose, replace, or recommend a recipe, the app sends information needed for that request directly to the AI provider you configured. Depending on the feature, this can include recipe text, captions, notes, source URLs, selected screenshots, ingredients, recipe titles, requested cuisine or dish, household-member names and selected likes or dislikes, region, stores, equipment, other recipe preferences, and the provider API key used to authenticate the request.

If provider fallback is enabled, the same request may be sent to additional configured providers until one completes it. Supported providers are Google Gemini, OpenAI, Anthropic Claude, and xAI Grok. Requests use HTTPS. Each provider handles data under its own account settings, retention rules, terms, and privacy policy. Apps by Dan does not receive or control data sent directly to those providers.

RECIPE LINKS
When you import a link, Pantry Logic may connect directly to that website to retrieve public recipe text. The website receives ordinary network information such as your IP address and request metadata. Retrieved text may be sent to your selected AI provider when it cannot be parsed locally.

SHARING, PRINTING, AND BACKUPS
Share and Print pass selected content to Android's share or print service only after you choose the action. Exported backups may contain recipes, profiles, plans, shopping data, history, and settings, but not API keys. You control where backup files are stored and shared.

NO ADS OR TRACKING
Pantry Logic contains no advertising, behavioral analytics, crash-reporting, or tracking SDKs. Apps by Dan does not sell personal information and does not operate a Pantry Logic server that receives your app data.

RETENTION AND DELETION
Local information remains until you delete it where a deletion control is available, clear Pantry Logic's storage, or uninstall the app. Backups remain where you saved them until you delete them. For information held by an AI provider or another third party, use that provider's privacy controls.

SECURITY
Pantry Logic uses Android app isolation, secure device storage for API keys, and HTTPS for supported network requests. Protect access to your device, backups, and API keys.

CHILDREN
Pantry Logic is a general-audience household utility and is not directed to children under 13.

CONTACT
For privacy questions, use the Pantry Logic project contact page at https://github.com/Crazyh1803/PantryLogic/issues. Do not post API keys or sensitive personal information in a public issue.
''';
