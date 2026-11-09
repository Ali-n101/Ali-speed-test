# ⚡ Ali-speed-test — اختصار قياس سرعة الإنترنت في ويندوز

اختصار سطح مكتب خفيف وسريع لنظام **Windows 10 / 11** يقيس سرعة الإنترنت مباشرة من سيرفرات **Speedtest.net** الرسمية (عبر أداة **Ookla Speedtest CLI** بصيغة JSONL كـ API مباشر) **بدون فتح المتصفح وبدون أي نافذة أوامر سوداء**.

---

## ✨ المميزات

- **بدون متصفح وبدون شاشة سوداء:** يعمل في الخلفية عبر مشغّل صامت (`launch-silent.vbs`).
- **دقة 100% من Speedtest.net:** يعتمد على المحرك الرسمي `Ookla Speedtest CLI` (`--format=jsonl`) لقياس السرعات العالية (Fibers / 5G) بنفس دقة الموقع تماماً.
- **نافذة منبثقة أنيقة (Modern Dark Popup) + إشعارات ويندوز (Toast Notifications):**
  - عرض مباشر (Real-time) لتقدم الفحص وسرعة **Download** و **Upload** بالميجابت (`Mbps`).
  - عرض زمن الاستجابة **Ping** و **Jitter** (`ms`) ونسبة فقد الحزم **Packet Loss**.
  - إظهار اسم مزود الخدمة (**ISP**) والسيرفر المتصل به.
  - زر **نسخ النتيجة (Copy Result)** وزر **فتح شهادة الفحص (Web Certificate)** وزر **إعادة الفحص (Re-test)**.
- **اختصار سطح مكتب + اختصار كيبورد:** ينشئ اختصاراً جاهزاً باسم `Speedtest` على سطح المكتب مع اختصار لوحة مفاتيح سريع `Ctrl + Alt + S`.

---

## 🚀 طريقة التثبيت والاستخدام (بضغطة واحدة)

1. قم بتحميل المشروع (عبر `git clone` أو تحميله كملف `ZIP` وفك الضغط عنه):
   ```powershell
   git clone https://github.com/Ali-n101/Ali-speed-test.git
   cd Ali-speed-test
   ```
2. اضغط مرتين على ملف **[`install.bat`](install.bat)**.
3. سيقوم المثبّت تلقائياً بـ:
   - تحميل أداة **Ookla Speedtest CLI** الرسمية (إن لم تكن مثبتة مسبقاً).
   - إنشاء اختصار **`Speedtest`** بأيقونة مميزة على **سطح المكتب (Desktop)**.
   - تفعيل اختصار الكيبورد السريع **`Ctrl + Alt + S`**.
   - تشغيل أول فحص سرعة لك فوراً!

---

## 🛠️ التشغيل بدون نافذة (إشعارات ويندوز فقط)

إذا رغبت بتشغيل الفحص بالخلفية مع الاكتفاء بإشعارات ويندوز (Toast Notification) فقط بدون النافذة المنبثقة:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File .\speedtest-runner.ps1 -NotificationOnly
```

---

## 📂 هيكل الملفات

| الملف | الوصف |
| :--- | :--- |
| [`install.bat`](install.bat) | ملف التثبيت السريع بضغطة مزدوجة. |
| [`setup.ps1`](setup.ps1) | سكربت التهيئة: يحمّل أداة Ookla الرسمية وينشئ اختصار سطح المكتب. |
| [`speedtest-runner.ps1`](speedtest-runner.ps1) | السكربت الرئيسي: يتصل بـ `speedtest.exe` بصيغة `JSONL` ويعرض النافذة المنبثقة وإشعارات النظام. |
| [`launch-silent.vbs`](launch-silent.vbs) | المشغّل الصامت لمنع ظهور شاشة الـ Console السوداء عند فتح الاختصار. |
| [`assets/speedtest.ico`](assets/speedtest.ico) | أيقونة اختصار سطح المكتب. |
