# macOS: Mac App Store (draft reference for mobile-app-planning)

Draft by miniMark's Claude, Nov 4, 2026, for the Zulal team to review and wire into the skill. Checked on Apple pages on **2026-11-04**. **Checked** = quote read on the page; **Unverified** = no Apple page found, or the page is ambiguous. Apple's ASC Help pages fetch directly; developer.apple.com/documentation and HIG need the `/tutorials/data/….json` form.

Applies to a sandboxed native Mac app sold through the Mac App Store. Everything in `store-readiness.md` (privacy forms, age ratings, review notes, EU trader status, Small Business Program, price scheduling) also applies to a Mac record unless this page says otherwise.

## 1. Rules that are Mac-only (App Review Guidelines, last updated Oct 16, 2026)

- **Checked, 2.4.5:** (i) "appropriately sandboxed" and only appropriate macOS APIs to modify other apps' data; (ii) packaged and submitted with Xcode technologies, no third-party installers, "self-contained, single app installation bundles" that "cannot install code or resources in shared locations"; (iii) no auto-launch or code run at startup or login without consent, no processes that keep running after quit, no automatic Dock icon or desktop shortcut; (iv) no downloading or installing standalone apps, kexts, "additional code, or resources to add functionality or significantly change the app from what we see during the review process"; (v) no root escalation or setuid; (vi) no license screen at launch, no license keys, no own copy protection; (vii) updates only through the Mac App Store; (viii) run on the currently shipping OS, no deprecated or optionally installed technologies (Java); (ix) all localization in one bundle. Source: https://developer.apple.com/app-store/review/guidelines/
- **Checked, 3.1.1:** Mac App Store apps "may host plug-ins or extensions that are enabled with mechanisms other than the App Store."
- **Checked, 2.5.6:** apps that browse the web must use WebKit and WebKit JavaScript. 2.5.2: self-contained, no code download that changes features. JavaScript libraries shipped inside the bundle are not downloaded code (our inference). 4.7 covers software "not embedded in the binary"; say in the review notes that all scripts ship in the bundle.
- **Checked, 5.1.1(i):** a privacy policy link in the App Store Connect field **and** "within the app in an easily accessible manner", even for an app that collects nothing. miniMark needed new Help-menu links for this. Mac apps often have no help book: replace the Help menu items with links.
- **Unverified:** whether remote content a user's document links to, loaded in a WKWebView, needs a stated justification for `network.client`. No Apple page says App Review requires written entitlement justification; explaining it in the review notes is common practice.

## 2. Signing and upload

- **Checked:** app identity "Apple Distribution: <Team Name> (<Team ID>)"; installer identity "3rd Party Mac Developer Installer" (Apple's certificate list calls the type Mac Installer Distribution). Pages: `documentation/xcode/creating-distribution-signed-code-for-the-mac`, `documentation/xcode/packaging-mac-software-for-distribution`, https://developer.apple.com/help/account/certificates/certificates-overview
- **Checked:** two routes. (a) Xcode: Archive, Organizer, Distribute App, App Store Connect; with automatic signing Xcode uses cloud-managed certificates, signs and uploads with symbols; Organizer also has Validate. (b) Manual: `productbuild --sign "<installer identity>" --component <App> /Applications <pkg>`, then altool or Transporter (the ASC API's JWTs also work for upload).
- **Checked, DTS forum thread 733942 (Jul 2023, revised Aug 2023):** a Mac app needs a provisioning profile only for restricted entitlements, but a TestFlight macOS build must carry one (error ITMS-90889). App Sandbox, user-selected files, bookmarks, network.client and print are unrestricted. **Unverified** on Xcode 27.
- **Checked:** notarization is for software distributed outside the store. **Unverified (absence of a statement):** hardened runtime is not required for Mac App Store builds.
- **Checked (upcoming-requirements, since Feb 18, 2025):** macOS apps must not carry the `com.apple.quarantine` attribute on any file.
- **Checked (ASC release notes, Oct 21, 2026):** uploads need Xcode 14 or later. The Apr 28, 2026 and Apr 2027 SDK floors name iOS, iPadOS, tvOS, visionOS and watchOS, **not macOS**; whether a macOS floor is enforced is **unverified**. Build with the current Xcode anyway.
- **Planning point:** a headless build user has no Xcode account and no distribution identity (our check on a build Mac found 0 identities, 0 profiles). Settle which Mac and Apple account does the archive before promising a date.
- Upload roles: Account Holder, Admin, App Manager or Developer.

## 3. Architecture and OS

- **Checked (News ?id=k1mtkt1k, Sep 9, 2026):** "To limit your app to Macs with Apple silicon, set your Xcode build architecture to arm64 only." macOS 26 is the last release for Intel Macs and Rosetta. News ?id=w5ngl9k2 (Sep 1, 2026) still advises universal binaries to keep Intel users. **Unverified** as a review risk: no Apple page lists arm64-only as a rejection reason.
- **Checked (ASC release notes, Jun 18, 2026):** a universal macOS app with a minimum system version of 13 or later can drop x86_64.

## 4. Info.plist and privacy files

- **Checked:** `LSApplicationCategoryType` (a category key, e.g. `public.app-category.productivity`; Apple does not say it is required, but the ASC category should match), `LSMinimumSystemVersion` (written from the deployment target; shows compatibility on the store page), `NSHumanReadableCopyright`, `ITSAppUsesNonExemptEncryption` (NO avoids the export question on every upload; whether HTTPS-only use is exempt is the developer's call).
- **Checked:** App Sandbox entitlement "is an App Store requirement for any app that you submit to the Mac App Store".
- **Checked:** `PrivacyInfo.xcprivacy` reasons: UserDefaults CA92.1 (data only the app reads), FileTimestamp 3B52.1 (metadata of files the user granted access to) and C617.1 (app container). **Unverified:** whether the required-reason rule is enforced on macOS uploads (the sibling page lists iOS, iPadOS, tvOS, visionOS, watchOS); a manifest is harmless either way.
- **Checked:** Apple's third-party SDK list has 86 entries; Swift packages such as swift-markdown-ui and Highlightr are not on it. Run Xcode's privacy report on the archive for transitive dependencies.

## 5. Listing for a Mac record

- **Checked (ASC screenshot specs; no date):** Mac screenshots are 16:10: 1280×800, 1440×900, 2560×1600 or 2880×1800, 1–10 per size, JPEG or PNG, "can't include alpha channels or transparencies" (release notes, Jul 8, 2026). App previews optional (1920×1080 landscape, 15–30 s, up to 3). **Unverified:** whether a Mac-only record also needs iPhone screenshots (the page is ambiguous); confirm in App Store Connect.
- **Checked:** name ≤30 (editable until submitted), subtitle ≤30, promotional text ≤170, description ≤4000 plain text, keywords ≤100 bytes, notes for review ≤4000 bytes, support URL must lead to real contact information, privacy policy URL required for macOS, copyright "name of the person or entity that owns the exclusive rights, preceded by the year" (ASC adds the symbol). **Unverified:** whether the secondary category is optional.
- **Checked:** the App Review contact phone must be in international format (release notes, Aug 19, 2026).
- Creating the record: Apps > + > New App; platform macOS; bundle ID cannot change after a build is uploaded; SKU cannot change; name availability behaviour at creation is **unverified**. The Account Holder must have signed the latest agreement first. The record is created by Account Holder, Admin or App Manager.
- **Checked:** TestFlight for Mac exists (Xcode 13+); external testing needs Beta App Review for the first build; builds last 90 days. **Checked (News ?id=ljpl7kyn, Oct 5, 2026):** the new asset library and creative assets are optional.
- **Unverified:** whether macOS has phased release (Apple's own pages disagree); irrelevant for version 1.0.
