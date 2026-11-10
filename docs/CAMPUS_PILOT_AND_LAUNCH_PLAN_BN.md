# PUST LiveBus: মাঠপরীক্ষা থেকে পুরো ক্যাম্পাসে চালুর পরিকল্পনা

প্রস্তুত: ২ নভেম্বর ২০২৬। এটি বর্তমান code, পূর্বের test ফল এবং ওই দিনের official provider documentation-এর ভিত্তিতে প্রস্তুতির মূল্যায়ন। কোনো billing plan বদলানো, বাড়তি driver account তৈরি বা বড় load test চালানো হয়নি। নিচের সময়সীমা ও মানদণ্ড পরিকল্পনার প্রস্তাব; অর্জিত performance দাবি নয়।

## বর্তমান অবস্থার সঠিক পরিচয়

Website public এবং install করার Android APK আছে। এটি সীমিত pilot-এর প্রস্তুতি নেওয়ার অবস্থায় আছে। ক্যাম্পাসের সবার দৈনন্দিন নির্ভরযোগ্য সেবা হিসেবে ঘোষণা দেওয়ার আগে বাস্তব বাস, ফোন, নেটওয়ার্ক ও মানুষের ব্যবহার দিয়ে পরীক্ষা দরকার।

যা ইতিমধ্যে যাচাই হয়েছে: ২৫টি Flutter test, ১০টি Firebase emulator permission test, web build, Android release build, APK signature ও alignment, bundled offline data/logo, Chrome navigation/location permission/offline reopening, এবং Hosting deployment। এগুলোতে physical driver phone দিয়ে চলন্ত বাসের দীর্ঘক্ষণ tracking, screen-off GPS, বহুজনের একসঙ্গে ব্যবহার, বাস্তব ETA error বা প্রকৃত মাসিক খরচ মাপা হয়নি।

## কতজন ব্যবহার করতে পারবে

Project-এর Cloud Billing API পরীক্ষা করে `billingEnabled: false` পাওয়া গেছে। Free Spark-এর relevant limits ধরেই এখন পরিকল্পনা করতে হবে। Realtime Database-এ Spark-এ ১০০ simultaneous connection, Blaze-এ প্রতি database-এ সর্বোচ্চ ২০০,০০০ connection-এর documented ceiling আছে। একটি connected browser tab বা app instance connection নেয়; অনেক data listener মানেই প্রত্যেকটি আলাদা connection নয়। APK এবং web একই Firebase project-এর quota ব্যবহার করে। ওই documented ceiling আমাদের অ্যাপের load-tested capacity নয়। [Firebase limits](https://firebase.google.com/docs/database/usage/limits)

Spark-এ Realtime Database storage ১ GB এবং downloads ১০ GB/month; Firebase Hosting transfer allowance ৩৬০ MB/day। এগুলো আলাদা quota। Plan upgrade করলে transfer/storage খরচও পর্যবেক্ষণ করতে হবে। [বর্তমান pricing](https://firebase.google.com/pricing)

সুতরাং ১০ হাজার মানুষ লিংক পেতে পারে বলেই ১০ হাজার মানুষ একসঙ্গে live bus দেখতে পারবে—এমন হিসাব করা যাবে না। Driver phones, viewer apps, extra tabs, admin ও test devices মিলিয়ে connection গণনা করতে হবে। Peak morning/afternoon usage ধরে sizing করতে হবে।

প্রথম pilot-এর প্রস্তাব: ১–২টি বাস এবং ১০–২০ জন viewer, পরে পর্যবেক্ষণ করে ২০–৩০ জন। এগুলো সাবধানী test-cohort size, performance guarantee নয়। বড় rollout-এর আগে আলাদা test project, প্রয়োজনীয় connection allowance, অনুমোদিত budget ও পর্যায়ক্রমিক load test লাগবে।

## এই code-এর খরচ ও scale concern

- `TransitRepository` welcome screen থেকেই database attach করে এবং সম্পূর্ণ `live` node শোনে। ফলে শুধু timetable দেখলেও সব বাসের GPS update আসতে পারে। প্রয়োজনের screen ও নির্বাচিত bus/route অনুযায়ী subscription সীমিত করা এবং background-এ অপ্রয়োজনীয় listener বন্ধ করা launch-এর আগের কাজ।
- Android driver GPS stream nominally ৫ সেকেন্ড interval চায়, distance filter ০; পাশাপাশি ১৫ সেকেন্ড heartbeat fix আছে। দুটো path থেকেই publish হতে পারে। একটি minimum publish interval, movement threshold এবং stationary heartbeat policy দিয়ে update rate নিয়ন্ত্রণ করা উচিত।
- শুধু বোঝানোর উদাহরণ: ১০টি বাস, ৫০০ connected viewer, প্রতি বাসে প্রতি ৫ সেকেন্ডে ৩০০-byte update ধরে সবাই সব update পেলে raw payload প্রায় ১.০৮ GB/hour। এটি measured usage বা bill নয়; initial downloads, reconnects ও protocol overhead আলাদা।
- বর্তমান offline shell-এর নির্বাচিত local files মোট প্রায় ২২.৫ MiB uncompressed; স্থানীয় gzip simulation প্রায় ১২.১ MiB। Hosting-এর প্রকৃত compressed transfer মাপা হয়নি। প্রথম visit-এর download, দুই CanvasKit variant precache এবং দুই logo version পর্যালোচনা করে কমানো উচিত। এই হিসাব দিয়ে নির্দিষ্ট daily visitor capacity দাবি করা যাবে না।
- Firebase Usage-এ connections, downloads, load এবং Hosting transfer দেখে ২০–৩০ মিনিটের controlled pilot-এর আগে/পরে পরিমাপ করো। Maps-এর provider traffic ও driver SIM-এর data আলাদাভাবে মাপবে। Firebase billing-এ connection/protocol overhead-ও থাকতে পারে। [Billing details](https://firebase.google.com/docs/database/usage/billing)
- Billing চালু করার আগে কে খরচ বহন করবে, মাসিক budget ও alert-এর দায়িত্ব নির্ধারণ করো। সাধারণ budget alert automatic hard spending cap নয়; Realtime Database ও classic Hosting-এর ক্ষেত্রে hard cap আছে ধরে নিও না। [Firebase cost controls](https://firebase.google.com/docs/projects/billing/avoid-surprise-bills)

## জরুরি ঝুঁকি এবং করণীয়

| বিষয় | এখন যা আছে/যা অনিশ্চিত | পূর্ণ rollout-এর আগে করণীয় |
|---|---|---|
| Official timetable | দেওয়া reference থেকে সময়; সব stop coordinate সম্পূর্ণ নয় | পরিবহন দপ্তরের তারিখসহ অনুমোদিত তালিকা, সব stop ও route যাচাই |
| ETA | প্রাথমিক speed/distance assumption; কিছু per-device observation শেখে | আসল stop arrival লিখে error মাপা; actual road path ও পর্যাপ্ত trip duration দিয়ে calibration |
| ETA range | Heuristic range; statistical confidence interval নয় | Demo ও UI-তে পরীক্ষামূলক পরিচয় রাখা; data ছাড়া নির্ভুলতার প্রতিশ্রুতি না দেওয়া |
| GPS reliability | Android foreground service configured; মাঠে দীর্ঘ পরীক্ষা হয়নি | screen off, battery saver, phone brand, accuracy, heat, charging ও পুরো trip পরীক্ষা |
| Browser driver tracking | Browser suspend হলে GPS থামতে পারে | Driver pilot-এ Android app ব্যবহার; আচরণ মাঠে যাচাই |
| Network interruption | এখন publishing বন্ধ হয়; reconnect-এর পর open trip close/start লাগতে পারে | নিরাপদ recovery workflow, orphan-session recovery এবং operator emergency stop প্রস্তুত |
| Driver phone | ফোন নড়লে bus-ও নড়ছে মনে হবে | অনুমোদিত ফোন, bus mount, charger/data; trip শেষে End Trip; off-duty tracking বন্ধ নিশ্চিত |
| GPS authenticity | Role/session checks ও basic mock checks আছে | ফোন আসল বাসেই আছে কি না operating process-এ নিশ্চিত; শুধু app দিয়ে physical identity প্রমাণের দাবি নয় |
| Driver roster | দশ slot-এর draft local device-এ থাকে | দশজনের real Auth UID, cloud assignment, shift/standby ও offboarding বাস্তবে যাচাই |
| Android signing | APK release build হলেও existing debug key দিয়ে signed | ব্যাপক distribution-এর আগে স্থায়ী release signing/update ব্যবস্থা; key-এর নিরাপদ backup |
| Passenger privacy | নিজের GPS একবার নেয়, window memory-তেই থাকে | সহজ privacy notice, permission-denied fallback, personal data প্রয়োজন ছাড়া না নেওয়া |
| Public bus GPS | বাসের latest location প্রকাশযোগ্য | কোন fleet/route/সময় public হবে পরিবহন দপ্তরের সঙ্গে অনুমোদন |
| Accounts/security | Admin claim ও assigned-driver rules পরীক্ষিত | আলাদা admin identity, Google owner account-এ 2-step verification, access review ও leaked account revoke প্রক্রিয়া |
| Abuse protection | Client App Check integration নেই | Android/web attestation integrate; metrics পর্যবেক্ষণের পরে enforcement; rules tests বজায় রাখা |
| Monitoring | Field incident/crash reporting প্রতিষ্ঠিত নয় | crash/error reporting, last-GPS/operator view, quota alerts, support contact ও দায়িত্ব |
| Recovery | Rules backup আছে; operational restore drill হয়নি | database/source/signing-key backup, restore drill, rollback build ও printed timetable fallback |
| Notification | Reminder app খোলা থাকলে দেখায় | Background push/arrival notification আলাদা feature; বর্তমানে আছে বলে প্রচার নয় |
| Maps | OSM public tiles ব্যবহার | attribution/cache/request policy যাচাই; বড় ব্যবহারে উপযুক্ত tile provider ও switching ব্যবস্থা |

Maps provider-এর volunteer tile service best-effort, SLA নেই এবং bulk offline tile download অনুমোদিত নয়। Data open হলেও tile server-এর unlimited capacity ধরে পরিকল্পনা করা যাবে না। [OSM policy](https://operations.osmfoundation.org/policies/tiles/)

App Check যোগ করলেই সব abuse বন্ধ হবে না; এটি Authentication ও rules-এর সঙ্গে বাড়তি সুরক্ষা। Enforcement চালুর আগে দুই platform-এর legitimate client যাচাই প্রয়োজন। [App Check](https://firebase.google.com/docs/app-check)

Android official distribution-এর signing ও versioning পরিকল্পনা এখনই ঠিক করা ভালো। নতুন signing key পুরোনো testing APK-এর সরাসরি update-এ সমস্যা করতে পারে; প্রচুর মানুষের ফোনে testing build ছড়ানোর আগে সিদ্ধান্ত নাও। [Android release guide](https://docs.flutter.dev/deployment/android)

## শিক্ষার্থী, শিক্ষক ও কর্মচারীদের কীভাবে যুক্ত করবে

১. পরিবহন দপ্তর থেকে প্রকৃত fleet list নাও: bus ID/number, active/maintenance status, route, stop order, weekday/holiday schedule, যাত্রী group এবং দায়িত্বপ্রাপ্ত driver। Reference-এ থাকা আটটি bus-ই পুরো campus fleet—এমন অনুমান করবে না।

২. Viewer হিসেবে প্রত্যেকের নাম/ফোন/account যোগ করা এখন প্রয়োজন নেই। বর্তমান public viewer screen সবাই দেখতে পারে, যদিও বাটনের নাম Student। সাধারণ viewer-কে student/staff/teacher সবার উপযোগী নাম এবং অনুমোদিত bus category/filter দেওয়া উচিত। Faculty/staff-only ও student service-এর ব্যবহারবিধি অফিসের তথ্য দিয়ে স্পষ্ট করো।

৩. Driver-এর real Authentication account তৈরি, UID assignment ও password recovery-এর মালিক নির্ধারণ করো। Draft slot আর working login আলাদা। একই bus-এর shift বদল, standby driver, previous open trip ও নতুন assignment যাচাই করো। কারও password chat বা group-এ পাঠাবে না।

৪. প্রথমে ১–২টি bus, তারপর approved route/fleet পর্যায়ক্রমে চালু করো। প্রতিটি driver-কে bus দাঁড়ানো অবস্থায় Start, End, network failure ও support procedure শেখাও। চালন্ত বাসে driver-কে app চালাতে বলবে না; পরীক্ষায় সহযাত্রী/helper থাকুক।

## প্রথম বাস্তব test-এর জন্য যা লাগবে

- পরিবহন দপ্তরের অনুমতি ও একটি নির্ধারিত bus/route; দায়িত্বপ্রাপ্ত একজন driver।
- Driver-এর Android phone: GPS, mobile data, charger/power bank ও phone mount।
- অন্তত দুই viewer phone; সম্ভব হলে একটি Android ও একটি iPhone/browser।
- Admin-এর laptop, আলাদা browser session ও প্রয়োজনীয় approved account।
- একজন সহযাত্রী/observer, যে stop arrival ও সমস্যা লিখবে।
- Office-verified stop/schedule list এবং একটি test log।
- Test কে থামাবে, সমস্যা হলে কাকে জানাবে এবং fallback timetable কোথায়—আগে নির্ধারণ।

প্রথম technical test parked bus-এর কাছে করো। তারপর একটি ছোট route, তারপর পূর্ণ trip। প্রথম দিনই peak passenger service-এর দায়িত্ব app-এর ওপর দিও না।

## মাঠপরীক্ষার checklist

| পরীক্ষা | কী করবে | কী দেখলে গ্রহণযোগ্য |
|---|---|---|
| Driver identity | সঠিক driver login, assigned bus/route নির্বাচন | অন্য bus-এ location publish করতে না পারা |
| Two sessions | দাঁড়ানো bus-এ দুই authorized phone থেকে একই bus start চেষ্টা | একটিই active trip; পরিষ্কার error/recovery |
| Start/End | actual trip start, finish ও viewer response | fresh bus দেখা; End-এর পরে sharing বন্ধ |
| Movement | একই bus-এ observer নিয়ে কয়েকটি stop যাওয়া | marker বাস্তব route-এর সঙ্গে মেলে; wrong-bus marker নেই |
| Screen off | অন্তত ৩০–৬০ মিনিট screen off ও app background | agreed GPS freshness বজায়; disconnect হলে stale label |
| Battery | battery saver ও কয়েকটি phone brand পরীক্ষা | কাজ বন্ধ হলে তা ধরা পড়ে; acceptable drain/heat |
| Network gap | নিরাপদ অবস্থায় data ২–৫ মিনিট বন্ধ করে আবার চালু | offline অবস্থানকে live না বলা; recovery বুঝে সম্পন্ন করা যায় |
| GPS failure | GPS/permission বন্ধ, poor accuracy, refresh | ভুল confidence নয়; কার্যকর fallback/error |
| Student permission | Allow, Deny, location clear এবং old fix | নিজের GPS শুধু অনুমতিতে; manual stop কাজ করে |
| Offline | প্রথম visit/install সম্পূর্ণ করে internet বন্ধ ও reopen | schedule/route খোলে; নতুন bus GPS দাবি করে না |
| ETA | target stop-এ prediction time ও actual arrival লিখে তুলনা | error report তৈরি; missing/ambiguous route-এ estimate withheld |
| Return route | একই stop দ্বিতীয়বার আসার সময় target occurrence বদল | outward/return মিশে না যাওয়া |
| Calendar | regular, holiday, date override, tomorrow, midnight | সঠিক দিনের planned schedule; আজকের GPS দিয়ে ভবিষ্যৎ arrival নয় |
| Admin | create/edit/archive, wrong references, active bus reassignment | valid save কাজ করে; unsafe/invalid operation rejected |
| Release update | পুরোনো web tab রেখে update; testing APK update | version বোঝা যায়; required data/sign-in পুনরুদ্ধার হয় |
| Support recovery | phone restart, trip না শেষ করে app বন্ধ, driver change | operator নিরাপদে recovery করতে পারে |

## Load এবং খরচ পরীক্ষা

Live production service-এ হঠাৎ শত শত fake user দিয়ে stress দেবে না। আলাদা staging project/database-এ test data ও অনুমোদিত budget ব্যবহার করবে। Spark সীমার ভেতর সব device/tab গুনে ধাপে ধাপে connections বাড়াবে; বড় peak-এর জন্য আগে যথাযথ plan নির্ধারণ করবে।

পরিমাপ করবে: concurrent connections, driver update rate, GPS age, update পৌঁছানোর delay, database download, Hosting download, crash count, data loss/duplicate session এবং viewer phone responsiveness। প্রথমে ২০ জন, পরে ৫০/৮০ total test session দিয়ে baseline নেওয়া যেতে পারে; শতাধিক test session বর্তমান Spark ceiling-এর সঙ্গে সামঞ্জস্যপূর্ণ নয়। বড় test-এর target university-র বাস্তব peak demand অনুযায়ী ঠিক করবে।

## Pilot-এর প্রস্তাবিত ধাপ

| ধাপ | প্রস্তাবিত পরিসর | পরের ধাপে যাওয়ার শর্ত |
|---|---|---|
| Bench test | ১ driver + ২ viewer phone; parked bus | login, start/end, permission ও correct bus কাজ করে |
| ছোট field pilot | ১ bus; কয়েকটি outward/return trip | screen-off, network gap, trip recovery ও stop positions যাচাই |
| নিয়মিত সীমিত pilot | ২ bus; ১০–৩০ মিশ্র viewer; অন্তত ৫ কর্মদিবস | একই সমস্যা বারবার না হওয়া; operator চালাতে পারে; log/report তৈরি |
| Approved expansion | আরও driver/bus; নিয়ন্ত্রিত বড় user cohort | load/cost/transport approval, signing ও support প্রস্তুত |
| Campus rollout | অফিস-অনুমোদিত fleet ও user communication | documented acceptance, দায়িত্ব ও fallback আছে |

## Launch acceptance criteria—প্রস্তাব, এখনও অর্জিত ফল নয়

- Safety/security: অন্য bus-এর GPS লেখা, অননুমোদিত admin save এবং student data leakage-এর সব critical test পাস।
- Operations: Start/End, driver change, internet ফিরে আসা এবং orphan session recovery transport operator নিজে করতে পারেন।
- Freshness: নির্ধারিত live tracking window-এর অন্তত ৯৫% sampled সময়ে driver fix ৩০ সেকেন্ডের কম পুরোনো রাখার লক্ষ্য; failing interval-এ stale/offline ঠিকমতো দেখানো। Coverage খারাপ হলে তা গোপন না করে সিদ্ধান্ত নিতে হবে।
- Stability: অন্তত ১০টি complete field trip ও ৫টি কর্মদিবসে unresolved critical crash/wrong-bus incident নেই।
- ETA: আগে route ও lookahead window স্থির করে error লক্ষ্য ঠিক করো। উদাহরণ হিসেবে ১০–১৫ মিনিট দূরের arrival-এ median absolute error ≤৩ মিনিট, P90 ≤৫ মিনিট লক্ষ্য নেওয়া যেতে পারে; এটি কোনো বর্তমান accuracy দাবি নয়। লক্ষ্য না মিটলে estimate-কে পরীক্ষামূলক রেখেই location-only service চালুর সিদ্ধান্ত নেওয়া যেতে পারে।
- Capacity: অনুমোদিত peak session target ও তার জন্য headroom-এ load test হয়েছে, quota/cost গ্রহণযোগ্য এবং alert কার কাছে যাবে জানা আছে।
- Content: পরিবহন দপ্তর timetable, stops, passenger group এবং holiday exception অনুমোদন করেছে।
- Distribution/support: স্থায়ী signing key, versioning, update/rollback plan, privacy notice, support contact, backup/restore drill ও দায়িত্বপ্রাপ্ত ব্যক্তি আছে।

## VC স্যারকে কখন এবং কীভাবে দেখাবে

এখন UI/feature prototype দেখিয়ে ছোট pilot-এর অনুমতি চাওয়া যায়। এতে real-world GPS বা campus-scale readiness প্রমাণ হয়েছে বলা যাবে না। একটি convincing live pilot demonstration-এর জন্য আগে অন্তত ১–২টি bus-এ কয়েক দিন বাস্তব পরীক্ষা করে log ও backup recording প্রস্তুত করা ভালো।

দেখানোর proposed flow: এক ফোনে authorized driver Start Trip; অন্য ফোনে correct bus দেখা; নিজের stop/approximate time; offline schedule; admin-এর approved timetable edit; network failure-এ honest stale/offline behaviour। Driver চলন্ত bus-এ phone operate করবেন না। একটি recorded demo রাখবে, কিন্তু সেটিকে live result হিসেবে উপস্থাপন করবে না।

সঙ্গে নেবে: ১ পাতার problem/benefit summary, architecture diagram, transport office-এর endorsement, pilot route/users/trip count, GPS freshness/ETA error/cost report, known limitations, next-step budget এবং বিশ্ববিদ্যালয়ের কাছ থেকে নির্দিষ্ট request। Request হতে পারে ২টি bus-এ pilot permission, official timetable, driver coordination, SIM/power support, এবং একজন IT/transport focal person।

পূর্ণ rollout-এর অনুমোদনের প্রস্তাব pilot evidence ও acceptance criteria পূরণের পরে দেবে। তারিখের চেয়ে প্রমাণকে সিদ্ধান্তের ভিত্তি করো।

## যা করবে না

- প্রথম দিন সব campus user-কে নির্ভর করতে বলবে না; আগে cohort-ভিত্তিক rollout।
- পরীক্ষামূলক অবস্থায় official university product বা নির্ভুল AI ETA দাবি করবে না।
- সবার নাম, roll, phone বা GPS শুধু account বাড়ানোর জন্য সংগ্রহ করবে না।
- Admin/owner password, service-account key বা signing key APK/repository/chat/group-এ দেবে না।
- কোনো সমস্যা ঢাকতে database public-write করে দেবে না।
- Billing alert-কে নিজে থেকে bill বন্ধ করার ব্যবস্থা ধরে নেবে না।
- ব্যক্তিগত driver ফোনে off-duty tracking চালু রাখবে না।
- বাসের নির্ধারিত সময়কে বাস বাস্তবে চলছে—এমন প্রমাণ ধরবে না।
- OSM standard server থেকে bulk offline maps download করবে না।
- Pilot report-এ বানানো user সংখ্যা, training data, uptime বা ETA accuracy লিখবে না।

## প্রতিটি trip-এর test log template

| তারিখ/সময় | App version | Bus/route | Driver device/Android | Trip start/end | Screen on/off | Network/SIM | Stop | Prediction made at | Predicted arrival | Actual arrival | GPS age/accuracy | Battery before/after | সমস্যা ও recovery | ফল |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| | | | | | | | | | | | | | | |

প্রতিদিন শেষে bug-এর severity, reproduction steps, owner এবং retest ফল লিখবে। Rollout-এর পরে timetable approval, driver onboarding/offboarding, daily monitoring এবং মাসিক cost review চালু রাখতে হবে।
