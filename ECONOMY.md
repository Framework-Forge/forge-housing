# Housing payments

Settings in `shared/config.lua`:
- `Config.impostos`: percentages for property sale remainder, furniture, water, electricity, IPTU, access charges and resale tax. Must total 100.
- `Config.security`: percentages for alarm / monitored-security purchases and recurring security bills. Must total 100.
- `Config.Commissions`: realtor grade fractions (0.10 = 10%). Only realtor sales pay a realtor commission.
- `Config.MinimumResalePercent = 50`: minimum private resale based on the current owner's acquisition price.
- `Config.TransferTaxPercent`: initial resale tax default; the boss can override in Services and fees.

The configured account IDs must exist in the banking provider used by PRBridge. The default real-estate account is `realestate`, matching the configured job, not the example spelling `realtestate`. Other defaults: `government`, `police`, `leo`.

The boss tablet manages service prices globally and bill amount/interval per property. Security bills start only after monitored security is purchased; arming/disarming does not stop billing. Changing a bill preserves outstanding debt and its next due date. Security subscriptions belong to the property and remain on ownership transfer.

Each successful purchase / transfer saves `purchase_price` with ownership. Existing owned properties without a historical purchase price are initialized once from their stored listing price. This is a migration fallback, not a reconstructed transaction history.

Private transfer: buyer pays the agreed price; tax is deducted from seller proceeds; seller receives net in their bank. The tablet displays acquisition basis, minimum price, gross, tax and net before confirmation. The buyer also confirms payment.

All payouts go through PRBridge. Cash charges use its inventory integration. Personal bank charges use its framework interface (QBX authoritative player balance); society credits use its banking interface. Renewed-Banking company-account lookups must not receive player source IDs. Society and beneficiary credits explicitly call the installed banking statement export, because addAccountMoney alone does not write transaction history. New descriptions include operation, character name/ID, property and purchased items or paid bill types; society entries also include the percentage. Existing historical entries are not rewritten. `data/economy.json` is a private server-only settings and payout journal; back it up with the database. Committed payouts are processed every five seconds; offline personal recipients wait until they reconnect. No automatic creation of society accounts occurs.

Missing/unavailable banking accounts leave payouts pending and are reported in the server console. A restart during an external credit or purchase commit can leave reserved/attempting/review records. These require operator reconciliation against banking logs; they are not automatically replayed, to avoid duplicate credits. Do not delete or reset the journal to fix a pending payout.

Currency amounts in existing furniture payments retain their existing nominal units; no cryptocurrency exchange rate is introduced.

Deploy by restarting forge-housing and then forge-realtor during maintenance. Validate actual account IDs, a realtor sale, a private resale, bills and cash/bank purchases in FiveM. Automated tests use simulated bridge/database services and do not substitute for these live checks.
