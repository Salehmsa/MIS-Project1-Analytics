/* =====================================================================
   المشروع : MIS Executive Analytics  (SQL Server)
   الملف   : MIS_Learning_Clean.sql
   الهدف   : بناء قاعدة MIS_Learning من الصفر بأمر واحد، وقابل لإعادة التشغيل.

   طريقة الاستخدام (3 خطوات)
   1) ضع مجلد data (فيه 5 ملفات CSV) في مسار يقرؤه حساب خدمة SQL Server،
      ثم عدّل المتغير @DataDir في القسم 4.
   2) شغّل الأقسام 0 إلى 4 (بناء + تحميل) ثم القسم 5 (تحقق).
   3) شغّل أي استعلام تحليلي من الأقسام 7 إلى 10 على حدة (حدّده ثم F5).

   تحذير: القسم 1 يحذف الجداول الخمسة ويعيد إنشاءها. لا تشغّله على
   بيانات تريد الاحتفاظ بها دون نسخة احتياطية. (جداول Tickets_Backup_*
   التي أنشأتها يدوياً لا تُمس.)

   ملاحظة: السكربت يتطلب SQL Server 2017 أو أحدث (FORMAT='CSV' و CREATE OR ALTER).
   ===================================================================== */


/* ---------------------------------------------------------------------
   القسم 0 | إنشاء القاعدة والعمل داخلها
   --------------------------------------------------------------------- */

-- [0.1] ملاحظة: السكربت القديم أنشأ القاعدة ثم لم يكتب USE، فذهبت الجداول
--       إلى قاعدة خاطئة. هنا ننشئ القاعدة فقط إن لم تكن موجودة، ثم ندخلها.
USE master;
GO
IF DB_ID(N'MIS_Learning') IS NULL
    CREATE DATABASE MIS_Learning;
GO
USE MIS_Learning;
GO
SET NOCOUNT ON;
GO


/* ---------------------------------------------------------------------
   القسم 1 | حذف الكائنات القديمة (لجعل السكربت قابلاً لإعادة التشغيل)
   --------------------------------------------------------------------- */

-- [1.1] ملاحظة: نحذف أولاً الـ Views ثم الجداول "الأبناء" ثم "الآباء"
--       بسبب المفاتيح الأجنبية. الشرط IF OBJECT_ID يمنع الخطأ عند أول تشغيل.
IF OBJECT_ID(N'dbo.vw_ProjectFinancials', N'V') IS NOT NULL DROP VIEW dbo.vw_ProjectFinancials;
IF OBJECT_ID(N'dbo.vw_TicketsEnriched',   N'V') IS NOT NULL DROP VIEW dbo.vw_TicketsEnriched;
IF OBJECT_ID(N'dbo.vw_AssetsEnriched',    N'V') IS NOT NULL DROP VIEW dbo.vw_AssetsEnriched;

IF OBJECT_ID(N'dbo.Tickets',  N'U') IS NOT NULL DROP TABLE dbo.Tickets;
IF OBJECT_ID(N'dbo.Assets',   N'U') IS NOT NULL DROP TABLE dbo.Assets;
IF OBJECT_ID(N'dbo.Projects', N'U') IS NOT NULL DROP TABLE dbo.Projects;
IF OBJECT_ID(N'dbo.Services', N'U') IS NOT NULL DROP TABLE dbo.Services;
IF OBJECT_ID(N'dbo.Clients',  N'U') IS NOT NULL DROP TABLE dbo.Clients;

IF OBJECT_ID(N'dbo.stg_Clients',  N'U') IS NOT NULL DROP TABLE dbo.stg_Clients;
IF OBJECT_ID(N'dbo.stg_Services', N'U') IS NOT NULL DROP TABLE dbo.stg_Services;
IF OBJECT_ID(N'dbo.stg_Projects', N'U') IS NOT NULL DROP TABLE dbo.stg_Projects;
IF OBJECT_ID(N'dbo.stg_Tickets',  N'U') IS NOT NULL DROP TABLE dbo.stg_Tickets;
IF OBJECT_ID(N'dbo.stg_Assets',   N'U') IS NOT NULL DROP TABLE dbo.stg_Assets;
GO


/* ---------------------------------------------------------------------
   القسم 2 | إنشاء الجداول (مع المفاتيح والقيود)
   ---------------------------------------------------------------------
   فلسفة التصميم: القيود تمنع البيانات الخاطئة من الدخول أصلاً، فلا نحتاج
   لاكتشافها لاحقاً. هذا ما كان ناقصاً في النسخة القديمة (بلا PK ولا FK).
   --------------------------------------------------------------------- */

-- [2.1] جدول العملاء (Dimension)
CREATE TABLE dbo.Clients
(
    ClientID    VARCHAR(10)   NOT NULL,
    ClientName  NVARCHAR(100) NOT NULL,
    Sector      NVARCHAR(50)  NOT NULL,
    Region      NVARCHAR(50)  NOT NULL,
    CONSTRAINT PK_Clients PRIMARY KEY (ClientID)
);

-- [2.2] جدول الخدمات (Dimension)
CREATE TABLE dbo.Services
(
    ServiceID    VARCHAR(10)   NOT NULL,
    ServiceName  NVARCHAR(100) NOT NULL,
    CONSTRAINT PK_Services PRIMARY KEY (ServiceID),
    CONSTRAINT UQ_Services_Name UNIQUE (ServiceName)
);

-- [2.3] جدول المشاريع (Fact)
-- ملاحظة القيود: لا إيراد/تكلفة سالبة، ونهاية المشروع لا تسبق بدايته،
-- وحالة المشروع محصورة بثلاث قيم معتمدة.
CREATE TABLE dbo.Projects
(
    ProjectID    VARCHAR(10)   NOT NULL,
    ProjectName  NVARCHAR(200) NOT NULL,
    ClientID     VARCHAR(10)   NOT NULL,
    ServiceID    VARCHAR(10)   NOT NULL,
    StartDate    DATE          NOT NULL,
    EndDate      DATE          NOT NULL,
    Revenue      DECIMAL(18,2) NOT NULL,
    Cost         DECIMAL(18,2) NOT NULL,
    Status       VARCHAR(20)   NOT NULL,
    CONSTRAINT PK_Projects PRIMARY KEY (ProjectID),
    CONSTRAINT FK_Projects_Clients  FOREIGN KEY (ClientID)  REFERENCES dbo.Clients(ClientID),
    CONSTRAINT FK_Projects_Services FOREIGN KEY (ServiceID) REFERENCES dbo.Services(ServiceID),
    CONSTRAINT CK_Projects_Amounts  CHECK (Revenue >= 0 AND Cost >= 0),
    CONSTRAINT CK_Projects_Dates    CHECK (EndDate >= StartDate),
    CONSTRAINT CK_Projects_Status   CHECK (Status IN ('Active','On Hold','Completed'))
);

-- [2.4] جدول التذاكر (Fact)
-- قرار تصميمي مهم: لا يوجد عمود ClientID هنا. العميل يُشتق من المشروع عبر
-- ProjectID، لأن وجود العمودين كان يسبب تناقضاً (45 من 50 تذكرة).
-- قيد CK_Tickets_OpenClosed يمنع الخلل الأصلي: التذكرة المفتوحة بلا تاريخ
-- إغلاق ولا ساعات حل، والمغلقة لا بد أن يكون لها الاثنان.
CREATE TABLE dbo.Tickets
(
    TicketID         VARCHAR(10) NOT NULL,
    ProjectID        VARCHAR(10) NOT NULL,
    CreatedDate      DATE        NOT NULL,
    ClosedDate       DATE        NULL,
    Priority         VARCHAR(10) NOT NULL,
    Status           VARCHAR(10) NOT NULL,
    ResolutionHours  SMALLINT    NULL,
    CONSTRAINT PK_Tickets PRIMARY KEY (TicketID),
    CONSTRAINT FK_Tickets_Projects FOREIGN KEY (ProjectID) REFERENCES dbo.Projects(ProjectID),
    CONSTRAINT CK_Tickets_Priority CHECK (Priority IN ('High','Medium','Low')),
    CONSTRAINT CK_Tickets_Status   CHECK (Status IN ('Open','Closed')),
    CONSTRAINT CK_Tickets_Dates    CHECK (ClosedDate IS NULL OR ClosedDate >= CreatedDate),
    CONSTRAINT CK_Tickets_OpenClosed CHECK
    (
        (Status = 'Open'   AND ClosedDate IS NULL     AND ResolutionHours IS NULL)
     OR (Status = 'Closed' AND ClosedDate IS NOT NULL AND ResolutionHours IS NOT NULL)
    )
);

-- [2.5] جدول الأصول (Fact)
CREATE TABLE dbo.Assets
(
    AssetID     VARCHAR(10)   NOT NULL,
    ClientID    VARCHAR(10)   NOT NULL,
    AssetType   VARCHAR(30)   NOT NULL,
    AssetValue  DECIMAL(18,2) NOT NULL,
    Status      VARCHAR(20)   NOT NULL,
    CONSTRAINT PK_Assets PRIMARY KEY (AssetID),
    CONSTRAINT FK_Assets_Clients FOREIGN KEY (ClientID) REFERENCES dbo.Clients(ClientID),
    CONSTRAINT CK_Assets_Value   CHECK (AssetValue >= 0),
    CONSTRAINT CK_Assets_Status  CHECK (Status IN ('Active','Retired'))
);

-- [2.6] فهارس على أعمدة الربط: تسرّع الـ JOIN في الاستعلامات و Power BI.
CREATE INDEX IX_Projects_ClientID  ON dbo.Projects (ClientID);
CREATE INDEX IX_Projects_ServiceID ON dbo.Projects (ServiceID);
CREATE INDEX IX_Tickets_ProjectID  ON dbo.Tickets  (ProjectID);
CREATE INDEX IX_Assets_ClientID    ON dbo.Assets   (ClientID);
GO


/* ---------------------------------------------------------------------
   القسم 3 | جداول التجهيز (Staging)
   ---------------------------------------------------------------------
   نحمّل الملفات أولاً كنصوص خام، ثم ننقلها للجداول النهائية مع تحويل
   الأنواع. السبب: عمود ClosedDate الفارغ في CSV يفشل مباشرة في عمود DATE،
   والتحويل الصريح يعطينا تحكماً كاملاً ورسائل خطأ أوضح.
   --------------------------------------------------------------------- */
CREATE TABLE dbo.stg_Clients  (ClientID NVARCHAR(100), ClientName NVARCHAR(200), Sector NVARCHAR(100), Region NVARCHAR(100));
CREATE TABLE dbo.stg_Services (ServiceID NVARCHAR(100), ServiceName NVARCHAR(200));
CREATE TABLE dbo.stg_Projects (ProjectID NVARCHAR(100), ProjectName NVARCHAR(200), ClientID NVARCHAR(100), ServiceID NVARCHAR(100),
                               StartDate NVARCHAR(50), EndDate NVARCHAR(50), Revenue NVARCHAR(50), Cost NVARCHAR(50), Status NVARCHAR(50));
CREATE TABLE dbo.stg_Tickets  (TicketID NVARCHAR(100), ProjectID NVARCHAR(100), CreatedDate NVARCHAR(50), ClosedDate NVARCHAR(50),
                               Priority NVARCHAR(50), Status NVARCHAR(50), ResolutionHours NVARCHAR(50));
CREATE TABLE dbo.stg_Assets   (AssetID NVARCHAR(100), ClientID NVARCHAR(100), AssetType NVARCHAR(100), AssetValue NVARCHAR(50), Status NVARCHAR(50));
GO


/* ---------------------------------------------------------------------
   القسم 4 | تحميل البيانات من ملفات CSV
   --------------------------------------------------------------------- */

-- [4.1] ملاحظة: عدّل المسار فقط. يجب أن ينتهي بـ \ ، وأن يملك حساب خدمة
--       SQL Server صلاحية القراءة عليه (وإلا يظهر الخطأ 4861).
--       بديل بلا مسارات: انقر بزر الماوس الأيمن على القاعدة
--       Tasks > Import Flat File لتحميل كل ملف إلى جدول stg_ المقابل.
DECLARE @DataDir NVARCHAR(260) = N'C:\MIS_Project\data\';

EXEC (N'BULK INSERT dbo.stg_Clients  FROM ''' + @DataDir + N'Clients.csv''  WITH (FORMAT=''CSV'', FIRSTROW=2, CODEPAGE=''65001'');');
EXEC (N'BULK INSERT dbo.stg_Services FROM ''' + @DataDir + N'Services.csv'' WITH (FORMAT=''CSV'', FIRSTROW=2, CODEPAGE=''65001'');');
EXEC (N'BULK INSERT dbo.stg_Projects FROM ''' + @DataDir + N'Projects.csv'' WITH (FORMAT=''CSV'', FIRSTROW=2, CODEPAGE=''65001'');');
EXEC (N'BULK INSERT dbo.stg_Tickets  FROM ''' + @DataDir + N'Tickets.csv''  WITH (FORMAT=''CSV'', FIRSTROW=2, CODEPAGE=''65001'');');
EXEC (N'BULK INSERT dbo.stg_Assets   FROM ''' + @DataDir + N'Assets.csv''   WITH (FORMAT=''CSV'', FIRSTROW=2, CODEPAGE=''65001'');');
GO

-- [4.2] نقل البيانات إلى الجداول النهائية بالترتيب الصحيح (الآباء قبل الأبناء).
--       القيم الفارغة أو الكلمة NULL في ClosedDate/ResolutionHours تتحول إلى NULL حقيقي.
INSERT INTO dbo.Clients (ClientID, ClientName, Sector, Region)
SELECT LTRIM(RTRIM(ClientID)), LTRIM(RTRIM(ClientName)), LTRIM(RTRIM(Sector)), LTRIM(RTRIM(Region))
FROM dbo.stg_Clients;

INSERT INTO dbo.Services (ServiceID, ServiceName)
SELECT LTRIM(RTRIM(ServiceID)), LTRIM(RTRIM(ServiceName))
FROM dbo.stg_Services;

INSERT INTO dbo.Projects (ProjectID, ProjectName, ClientID, ServiceID, StartDate, EndDate, Revenue, Cost, Status)
SELECT LTRIM(RTRIM(ProjectID)), LTRIM(RTRIM(ProjectName)), LTRIM(RTRIM(ClientID)), LTRIM(RTRIM(ServiceID)),
       CONVERT(DATE, LTRIM(RTRIM(StartDate)), 23), CONVERT(DATE, LTRIM(RTRIM(EndDate)), 23),
       CAST(Revenue AS DECIMAL(18,2)), CAST(Cost AS DECIMAL(18,2)), LTRIM(RTRIM(Status))
FROM dbo.stg_Projects;

INSERT INTO dbo.Tickets (TicketID, ProjectID, CreatedDate, ClosedDate, Priority, Status, ResolutionHours)
SELECT LTRIM(RTRIM(TicketID)), LTRIM(RTRIM(ProjectID)),
       CONVERT(DATE, LTRIM(RTRIM(CreatedDate)), 23),
       TRY_CONVERT(DATE, NULLIF(NULLIF(LTRIM(RTRIM(ClosedDate)), ''), 'NULL'), 23),
       LTRIM(RTRIM(Priority)), LTRIM(RTRIM(Status)),
       TRY_CAST(NULLIF(NULLIF(LTRIM(RTRIM(ResolutionHours)), ''), 'NULL') AS SMALLINT)
FROM dbo.stg_Tickets;

INSERT INTO dbo.Assets (AssetID, ClientID, AssetType, AssetValue, Status)
SELECT LTRIM(RTRIM(AssetID)), LTRIM(RTRIM(ClientID)), LTRIM(RTRIM(AssetType)),
       CAST(AssetValue AS DECIMAL(18,2)), LTRIM(RTRIM(Status))
FROM dbo.stg_Assets;

-- [4.3] تنظيف: لم نعد بحاجة لجداول التجهيز.
DROP TABLE dbo.stg_Clients, dbo.stg_Services, dbo.stg_Projects, dbo.stg_Tickets, dbo.stg_Assets;
GO


/* ---------------------------------------------------------------------
   القسم 5 | التحقق من التحميل
   --------------------------------------------------------------------- */

-- [5.1] مقارنة عدد الصفوف بالمتوقع.
-- الهدف : التأكد أن لا صف ضاع أثناء التحميل.
-- النتيجة المتوقعة: عمود Result = OK لكل الجداول الخمسة.
SELECT TableName, RowsCount, Expected,
       CASE WHEN RowsCount = Expected THEN 'OK' ELSE 'CHECK' END AS Result
FROM (
    SELECT 'Clients'  AS TableName, COUNT(*) AS RowsCount, 10 AS Expected FROM dbo.Clients  UNION ALL
    SELECT 'Services',              COUNT(*),               4             FROM dbo.Services UNION ALL
    SELECT 'Projects',              COUNT(*),               20            FROM dbo.Projects UNION ALL
    SELECT 'Tickets',               COUNT(*),               50            FROM dbo.Tickets  UNION ALL
    SELECT 'Assets',                COUNT(*),               40            FROM dbo.Assets
) AS x
ORDER BY TableName;

-- [5.2] ملاحظة: فحوصات المفاتيح المكررة والقيم الفارغة والعلاقات اليتيمة
--       لم تعد لازمة، لأن PK و FK و NOT NULL تضمنها تلقائياً (لو كان فيها
--       خلل لفشل التحميل برسالة خطأ). الفحوصات المنطقية موجودة في القسم 10.
GO


/* ---------------------------------------------------------------------
   القسم 6 | الـ Views (طبقة جاهزة للتحليل و Power BI)
   ---------------------------------------------------------------------
   فكرة: بدل تكرار الـ JOIN في كل استعلام، نبنيه مرة واحدة هنا. وفي
   Power BI يمكن الاتصال بهذه الـ Views مباشرة.
   --------------------------------------------------------------------- */

-- [6.1] vw_ProjectFinancials: صف لكل مشروع مع العميل والخدمة والربح والهامش
--       وعدد أيام التأخر. الهامش = (الإيراد - التكلفة) / الإيراد.
--       التأخر: مشروع غير مكتمل وتاريخ نهايته المخطط قبل اليوم.
CREATE OR ALTER VIEW dbo.vw_ProjectFinancials AS
SELECT  p.ProjectID, p.ProjectName,
        p.ClientID, c.ClientName, c.Sector, c.Region,
        p.ServiceID, s.ServiceName,
        p.StartDate, p.EndDate, p.Status,
        p.Revenue, p.Cost,
        p.Revenue - p.Cost AS Profit,
        CAST(100.0 * (p.Revenue - p.Cost) / NULLIF(p.Revenue, 0) AS DECIMAL(5,2)) AS MarginPct,
        CASE WHEN p.Status <> 'Completed' AND p.EndDate < CAST(GETDATE() AS DATE)
             THEN DATEDIFF(DAY, p.EndDate, CAST(GETDATE() AS DATE)) ELSE 0 END AS DaysOverdue
FROM dbo.Projects p
JOIN dbo.Clients  c ON c.ClientID  = p.ClientID
JOIN dbo.Services s ON s.ServiceID = p.ServiceID;
GO

-- [6.2] vw_TicketsEnriched: التذكرة مع مشروعها وعميلها (العميل مشتق من المشروع).
CREATE OR ALTER VIEW dbo.vw_TicketsEnriched AS
SELECT  t.TicketID, t.ProjectID, p.ClientID, c.ClientName, c.Sector, c.Region,
        p.ServiceID, t.CreatedDate, t.ClosedDate, t.Priority, t.Status, t.ResolutionHours
FROM dbo.Tickets  t
JOIN dbo.Projects p ON p.ProjectID = t.ProjectID
JOIN dbo.Clients  c ON c.ClientID  = p.ClientID;
GO

-- [6.3] vw_AssetsEnriched: الأصل مع عميله.
CREATE OR ALTER VIEW dbo.vw_AssetsEnriched AS
SELECT  a.AssetID, a.ClientID, c.ClientName, c.Sector, c.Region,
        a.AssetType, a.AssetValue, a.Status
FROM dbo.Assets  a
JOIN dbo.Clients c ON c.ClientID = a.ClientID;
GO


/* =====================================================================
   القسم 7 إلى 9 | الاستعلامات التحليلية
   (كل استعلام مستقل: حدّده ثم F5. القيم المتوقعة محسوبة من الملفات الحالية.)
   ===================================================================== */

/* ---------- أ) المشاريع والإيرادات (القسم 7) ---------- */

-- [7.1] المؤشرات الرئيسية للمحفظة
-- الهدف : الأرقام الستة التي تظهر في أعلى لوحة المدير.
-- كيف تقرأ: Revenue هنا = قيمة العقود الكاملة بغض النظر عن حالتها.
-- المتوقع : مشاريع 20 | إيراد 18,528,173 | تكلفة 13,403,954 | ربح 5,124,219 | هامش 27.66
SELECT  COUNT(*)                                                         AS ProjectsCount,
        SUM(Revenue)                                                     AS TotalRevenue,
        SUM(Cost)                                                        AS TotalCost,
        SUM(Revenue - Cost)                                              AS Profit,
        CAST(100.0 * SUM(Revenue - Cost) / NULLIF(SUM(Revenue), 0) AS DECIMAL(5,2)) AS MarginPct
FROM dbo.Projects;

-- [7.2] توزيع المشاريع حسب الحالة مع الإيراد
-- الهدف : معرفة كم من العقود مكتمل فعلاً وكم منها معلّق.
-- كيف تقرأ: ركّز على صف On Hold: إيراد لم يتحقق ويُحسب ضمن الإجمالي.
-- المتوقع : Completed 10 (8,635,307) | On Hold 6 (5,597,135) | Active 4 (4,295,731)
SELECT  Status,
        COUNT(*)                                                         AS ProjectsCount,
        SUM(Revenue)                                                     AS Revenue,
        CAST(100.0 * SUM(Revenue) / SUM(SUM(Revenue)) OVER () AS DECIMAL(5,2)) AS RevenueSharePct
FROM dbo.Projects
GROUP BY Status
ORDER BY Revenue DESC;

-- [7.3] الربحية حسب الخدمة
-- الهدف : اكتشاف أي خدمة تربح أكثر، وليس فقط أيها تبيع أكثر.
-- كيف تقرأ: قارن ترتيب الإيراد بترتيب الهامش. الاختلاف بينهما هو القصة.
-- المتوقع : IT Consulting أعلى هامش 34.56 | Technical Support أعلى إيراد (7,538,879) بهامش 29.59
--            | System Integration 24.42 | Managed Services أضعف هامش 20.51
SELECT  ServiceName,
        COUNT(*)                                                         AS ProjectsCount,
        SUM(Revenue)                                                     AS Revenue,
        SUM(Profit)                                                      AS Profit,
        CAST(100.0 * SUM(Profit) / NULLIF(SUM(Revenue), 0) AS DECIMAL(5,2)) AS MarginPct
FROM dbo.vw_ProjectFinancials
GROUP BY ServiceName
ORDER BY MarginPct DESC;

-- [7.4] الأداء حسب المنطقة
-- المتوقع : Riyadh 8 مشاريع (7,293,641) هامش 33.62 | Jeddah 7 (6,923,627) هامش 22.70
--            | Dammam 5 (4,310,905) هامش 25.52
SELECT  Region,
        COUNT(*)                                                         AS ProjectsCount,
        SUM(Revenue)                                                     AS Revenue,
        SUM(Profit)                                                      AS Profit,
        CAST(100.0 * SUM(Profit) / NULLIF(SUM(Revenue), 0) AS DECIMAL(5,2)) AS MarginPct
FROM dbo.vw_ProjectFinancials
GROUP BY Region
ORDER BY Revenue DESC;

-- [7.5] الأداء حسب القطاع
-- كيف تقرأ: القطاع الحكومي أقل هامش، أي أن أحجام العقود الحكومية لا تعوّض ضعف التسعير.
-- المتوقع : Finance 7 (6,113,339) هامش 28.97 | Telecom 5 (5,176,440) هامش 32.55
--            | Healthcare 5 (4,310,905) هامش 25.52 | Government 3 (2,927,489) هامش 19.41
SELECT  Sector,
        COUNT(*)                                                         AS ProjectsCount,
        SUM(Revenue)                                                     AS Revenue,
        CAST(100.0 * SUM(Profit) / NULLIF(SUM(Revenue), 0) AS DECIMAL(5,2)) AS MarginPct
FROM dbo.vw_ProjectFinancials
GROUP BY Sector
ORDER BY Revenue DESC;

-- [7.6] أكبر العملاء حسب الإيراد
-- المتوقع : Client 3 (3,708,987) ثم Client 10 (2,940,278) ثم Client 2 (2,939,515)
SELECT  ClientName,
        COUNT(*)                                                         AS ProjectsCount,
        SUM(Revenue)                                                     AS Revenue,
        SUM(Profit)                                                      AS Profit,
        CAST(100.0 * SUM(Profit) / NULLIF(SUM(Revenue), 0) AS DECIMAL(5,2)) AS MarginPct
FROM dbo.vw_ProjectFinancials
GROUP BY ClientName
ORDER BY Revenue DESC;

-- [7.7] تركّز الإيراد في أكبر 3 عملاء
-- الهدف : قياس خطر الاعتماد على عدد قليل من العملاء.
-- كيف تقرأ: أكثر من 50% يعني أن فقدان عميل واحد يهز المحفظة.
-- المتوقع : Top3SharePct = 51.75
WITH ClientRevenue AS (
    SELECT ClientID, SUM(Revenue) AS Rev FROM dbo.Projects GROUP BY ClientID
), Ranked AS (
    SELECT Rev, ROW_NUMBER() OVER (ORDER BY Rev DESC) AS rn FROM ClientRevenue
)
SELECT CAST(100.0 * SUM(CASE WHEN rn <= 3 THEN Rev END) / NULLIF(SUM(Rev), 0) AS DECIMAL(5,2)) AS Top3SharePct
FROM Ranked;

-- [7.8] متوسط قيمة المشروع حسب الخدمة
-- المتوقع : متوسط المحفظة 926,408.65 تقريباً.
SELECT  ServiceName,
        COUNT(*)                         AS ProjectsCount,
        CAST(AVG(Revenue) AS DECIMAL(18,2)) AS AvgProjectRevenue
FROM dbo.vw_ProjectFinancials
GROUP BY ServiceName
ORDER BY AvgProjectRevenue DESC;

-- [7.9] الإيراد حسب شهر بدء المشروع
-- ملاحظة مهمة: كل قيمة العقد تُنسب إلى شهر البدء (مثل ربط DimDate في Power BI).
--             لذلك 2026 يبدو ضعيفاً (790,795 فقط) وهذا لا يعني تراجع الأعمال.
-- المتوقع : 2025-01 = 2,180,014 | 2025-12 = 2,914,231 | 2026-02 = 790,795 | آخر تراكمي = 18,528,173
SELECT  CONVERT(CHAR(7), StartDate, 120) AS StartMonth,
        COUNT(*)                         AS ProjectsStarted,
        SUM(Revenue)                     AS ContractValue,
        SUM(SUM(Revenue)) OVER (ORDER BY CONVERT(CHAR(7), StartDate, 120)) AS CumulativeValue
FROM dbo.Projects
GROUP BY CONVERT(CHAR(7), StartDate, 120)
ORDER BY StartMonth;


/* ---------- ب) المخاطر (تابع للقسم 7) ---------- */

-- [7.10] الإيراد المعلّق (On Hold) كنسبة من الإجمالي
-- المتوقع : OnHoldRevenue = 5,597,135 | OnHoldSharePct = 30.21
SELECT  SUM(CASE WHEN Status = 'On Hold' THEN Revenue ELSE 0 END)        AS OnHoldRevenue,
        CAST(100.0 * SUM(CASE WHEN Status = 'On Hold' THEN Revenue ELSE 0 END)
             / NULLIF(SUM(Revenue), 0) AS DECIMAL(5,2))                  AS OnHoldSharePct
FROM dbo.Projects;

-- [7.11] المشاريع المتأخرة عن موعدها
-- الهدف : قائمة المشاريع غير المكتملة التي تجاوزت تاريخ نهايتها.
-- كيف تقرأ: DaysOverdue كبير = إما حالة قديمة لم تُحدَّث أو تأخر فعلي.
-- المتوقع : 10 صفوف (كل المشاريع غير المكتملة) عند التشغيل بعد 2026-07-26.
SELECT  ProjectID, ClientName, ServiceName, Status, EndDate, DaysOverdue, Revenue
FROM dbo.vw_ProjectFinancials
WHERE DaysOverdue > 0
ORDER BY DaysOverdue DESC;

-- [7.12] العملاء بلا مشاريع
-- الهدف : فرص مبيعات محتملة أو سجلات خاملة.
-- المتوقع : صف واحد: C006 (Client 6, Government, Jeddah).
SELECT  c.*
FROM dbo.Clients c
LEFT JOIN dbo.Projects p ON p.ClientID = c.ClientID
WHERE p.ProjectID IS NULL;


/* ===================== القسم 8 | التذاكر والدعم ===================== */

-- [8.1] تذاكر مفتوحة ومغلقة (الأعداد)
-- المتوقع : Open 27 | Closed 23.
SELECT  Status, COUNT(*) AS TicketsCount
FROM dbo.Tickets
GROUP BY Status;

-- [8.2] التذاكر حسب الأولوية والحالة
-- كيف تقرأ: الأولوية العالية المفتوحة هي الأخطر.
-- المتوقع : High 10 (7 مفتوحة) | Medium 26 (14 مفتوحة) | Low 14 (6 مفتوحة)
SELECT  Priority,
        COUNT(*)                                          AS TotalTickets,
        SUM(CASE WHEN Status = 'Open'   THEN 1 ELSE 0 END) AS OpenTickets,
        SUM(CASE WHEN Status = 'Closed' THEN 1 ELSE 0 END) AS ClosedTickets
FROM dbo.Tickets
GROUP BY Priority
ORDER BY CASE Priority WHEN 'High' THEN 1 WHEN 'Medium' THEN 2 ELSE 3 END;

-- [8.3] متوسط ساعات الحل حسب الأولوية (التذاكر المغلقة فقط)
-- ملاحظة: المفتوحة بلا ساعات حل (NULL)، و AVG يتجاهل NULL تلقائياً، فالنتيجة صحيحة.
-- كيف تقرأ: لو كانت الأولوية العالية أبطأ أو تساوي المنخفضة، فنظام الأولويات لا يعمل.
-- المتوقع : High 14.33 (3 تذاكر) | Medium 10.42 (12) | Low 11.63 (8) | الإجمالي 11.35
SELECT  Priority,
        COUNT(ResolutionHours)                         AS ClosedTickets,
        CAST(AVG(CAST(ResolutionHours AS DECIMAL(9,2))) AS DECIMAL(9,2)) AS AvgResolutionHours
FROM dbo.Tickets
GROUP BY Priority
ORDER BY CASE Priority WHEN 'High' THEN 1 WHEN 'Medium' THEN 2 ELSE 3 END;

-- [8.4] نسبة الالتزام بالـ SLA
-- ملاحظة: حد الـ SLA هنا 8 ساعات (افتراض). عدّل @SLA_Hours للحد الحقيقي.
--         المقام = التذاكر المغلقة فقط، لأن المفتوحة لم تُحل بعد.
-- المتوقع : عند 8 ساعات: 10 من 23 = 43.48 | عند 4: 13.04 | عند 24: 100
DECLARE @SLA_Hours INT = 8;
SELECT  @SLA_Hours                                                      AS SLA_Hours,
        SUM(CASE WHEN Status = 'Closed' AND ResolutionHours <= @SLA_Hours THEN 1 ELSE 0 END) AS WithinSLA,
        SUM(CASE WHEN Status = 'Closed' THEN 1 ELSE 0 END)              AS ClosedTickets,
        CAST(100.0 * SUM(CASE WHEN Status = 'Closed' AND ResolutionHours <= @SLA_Hours THEN 1 ELSE 0 END)
             / NULLIF(SUM(CASE WHEN Status = 'Closed' THEN 1 ELSE 0 END), 0) AS DECIMAL(5,2)) AS SLAPct
FROM dbo.Tickets;

-- [8.5] التذاكر حسب العميل (مشتق من المشروع)
-- الهدف : من أكثر عميل يستهلك الدعم، وكم ما زال مفتوحاً عنده.
-- المتوقع : Client 3 = 13 (8 مفتوحة) | Client 10 = 11 (7) | Client 7 = 8 (4) | Client 1 = 6 (3)
--            Client 9 = 4 | Client 2 = 3 | Client 5 = 3 | Client 8 = 2
SELECT  ClientName,
        COUNT(*)                                          AS TotalTickets,
        SUM(CASE WHEN Status = 'Open' THEN 1 ELSE 0 END)  AS OpenTickets
FROM dbo.vw_TicketsEnriched
GROUP BY ClientName
ORDER BY TotalTickets DESC;

-- [8.6] التذاكر المنشأة شهرياً
-- المتوقع : 2025-01=4 | 2025-02=5 | ... | 2026-01=7 (الذروة) | 2026-05=1
SELECT  CONVERT(CHAR(7), CreatedDate, 120) AS CreatedMonth,
        COUNT(*)                           AS TicketsCreated
FROM dbo.Tickets
GROUP BY CONVERT(CHAR(7), CreatedDate, 120)
ORDER BY CreatedMonth;

-- [8.7] التذاكر المفتوحة عالية الأولوية (قائمة العمل العاجلة)
-- المتوقع : 7 صفوف. DaysOpen يُحسب حتى اليوم.
SELECT  TicketID, ProjectID, ClientName, CreatedDate,
        DATEDIFF(DAY, CreatedDate, CAST(GETDATE() AS DATE)) AS DaysOpen
FROM dbo.vw_TicketsEnriched
WHERE Status = 'Open' AND Priority = 'High'
ORDER BY CreatedDate;


/* ===================== القسم 9 | الأصول ===================== */

-- [9.1] الأصول حسب الحالة: العدد والقيمة
-- كيف تقرأ: قيمة "Retired" لا تدخل في رأس المال العامل الفعلي.
-- المتوقع : Active 17 (1,282,893) | Retired 23 (1,382,380) | الإجمالي 2,665,273
SELECT  Status,
        COUNT(*)        AS AssetsCount,
        SUM(AssetValue) AS AssetValue,
        CAST(100.0 * SUM(AssetValue) / SUM(SUM(AssetValue)) OVER () AS DECIMAL(5,2)) AS ValueSharePct
FROM dbo.Assets
GROUP BY Status;

-- [9.2] الأصول حسب النوع والحالة
-- كيف تقرأ: الشبكات هي الأكثر خروجاً من الخدمة (8 من 12).
-- المتوقع : Network 12 (4 فعّال / 8 متقاعد) | Laptop 10 (5/5) | Server 9 (4/5) | Storage 9 (4/5)
SELECT  AssetType,
        COUNT(*)                                             AS AssetsCount,
        SUM(CASE WHEN Status = 'Active'  THEN 1 ELSE 0 END)  AS ActiveCount,
        SUM(CASE WHEN Status = 'Retired' THEN 1 ELSE 0 END)  AS RetiredCount,
        SUM(CASE WHEN Status = 'Active'  THEN AssetValue ELSE 0 END) AS ActiveValue,
        SUM(CASE WHEN Status = 'Retired' THEN AssetValue ELSE 0 END) AS RetiredValue
FROM dbo.Assets
GROUP BY AssetType
ORDER BY AssetsCount DESC;

-- [9.3] الأصول حسب العميل
-- المتوقع : Client 4 = 7 | Client 9 = 6 | Client 7 = 5 | Clients 2,3,5 = 4 لكل منها
SELECT  ClientName,
        COUNT(*)        AS AssetsCount,
        SUM(AssetValue) AS AssetValue
FROM dbo.vw_AssetsEnriched
GROUP BY ClientName
ORDER BY AssetsCount DESC, AssetValue DESC;


/* =====================================================================
   القسم 10 | فحوصات جودة البيانات المنطقية
   (القيود تحمي من الأخطاء الهيكلية، وهذه الفحوصات تكشف الأخطاء المنطقية)
   ===================================================================== */

-- [10.1] تذاكر أُنشئت خارج الفترة الزمنية لمشروعها
-- الهدف : تذكرة قبل بدء المشروع أو بعد انتهائه غالباً مرتبطة بمشروع خاطئ.
-- المتوقع : 34 صفاً (مشكلة معروفة في البيانات الحالية، تحتاج مراجعة مع مصدرها).
SELECT  t.TicketID, t.ProjectID, t.CreatedDate, p.StartDate, p.EndDate,
        CASE WHEN t.CreatedDate < p.StartDate THEN 'Before start' ELSE 'After end' END AS Issue
FROM dbo.Tickets  t
JOIN dbo.Projects p ON p.ProjectID = t.ProjectID
WHERE t.CreatedDate < p.StartDate OR t.CreatedDate > p.EndDate
ORDER BY t.TicketID;

-- [10.2] مشاريع غير مكتملة تجاوزت موعدها (عدد فقط)
-- المتوقع : 10 من 10. إن بقي الرقم كذلك فحدّث الحالات أو اعتمد أن المحفظة متأخرة.
SELECT  SUM(CASE WHEN Status <> 'Completed' AND EndDate < CAST(GETDATE() AS DATE) THEN 1 ELSE 0 END) AS OverdueProjects,
        SUM(CASE WHEN Status <> 'Completed' THEN 1 ELSE 0 END)                                       AS UnfinishedProjects
FROM dbo.Projects;

-- [10.3] اتساق حالة التذكرة مع تاريخ الإغلاق
-- الهدف : التأكد أن الخلل الأصلي (مفتوحة بتاريخ إغلاق) لم يعد.
-- المتوقع : 0 صفوف. (القيد CK_Tickets_OpenClosed يمنع حدوثه أصلاً.)
SELECT  TicketID, Status, ClosedDate, ResolutionHours
FROM dbo.Tickets
WHERE (Status = 'Open'   AND (ClosedDate IS NOT NULL OR ResolutionHours IS NOT NULL))
   OR (Status = 'Closed' AND (ClosedDate IS NULL     OR ResolutionHours IS NULL));

-- [10.4] مشاريع هامشها منخفض جداً (أقل من 20%)
-- الهدف : عقود مسعّرة بأقل من الحد المقبول، لمراجعة التسعير.
-- المتوقع : 5 صفوف: P019 (15.00) ثم P007 و P017 (17.00) ثم P009 و P020 (19.00).
SELECT  ProjectID, ClientName, ServiceName, Status, Revenue, Cost, MarginPct
FROM dbo.vw_ProjectFinancials
WHERE MarginPct < 20
ORDER BY MarginPct;

/* ===================== نهاية السكربت ===================== */
