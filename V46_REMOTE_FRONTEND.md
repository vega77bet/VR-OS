# V46 — Interface remota configurável

V46 adds a data-only remote frontend configuration.

The app can update without a new IPA:
- taskbar order;
- taskbar labels;
- visibility of known actions;
- selection of local icon assets;
- accent and surface colors;
- taskbar opacity;
- remote text/window templates already supported by the manifest.

Safety:
- only HTTPS JSON is accepted;
- the manifest is size-limited and schema-validated before mutation;
- action and icon identifiers are allow-listed;
- no Swift, JavaScript, frameworks, IPA or executable payload is downloaded;
- the last valid cache remains available offline;
- the app falls back to the built-in configuration if the endpoint fails.

The endpoint must be a public HTTPS JSON host. The GitHub repository itself is private,
so a GitHub token is deliberately not embedded in the app. Changing the actual native
code or adding brand-new native behavior still requires a new signed IPA.
