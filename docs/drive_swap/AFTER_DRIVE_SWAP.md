# אחרי החלפת הכונן (6.10.2026)

**הכונן הישן:** Kingston NVMe‏ 2 TB, מחיצות C: ו-D:.
**הכונן החדש:** Samsung 990 PRO‏ 4 TB, יהיה C:.
**לוח האם:** MSI B650M GAMING WIFI. שני חריצי ה-M.2 הם PCIe 4.0 x4 מהמעבד, אז אין צורך להחליף מיקומים.
**השיטה המומלצת:** שיבוט עם Samsung Data Migration (בתוך Samsung Magician).

**כלל אחד מעל הכל:** לא לפרמט את הכונן הישן עד שכל הבדיקות כאן עוברות, ורצוי שבוע של עבודה תקינה.

## 0. לפני ההחלפה (בוצע ב-6.10, ‏19:15–20:15)
- **git:** כל ה-worktrees עברו commit, וכל ה-branches ב-GitHub (`https://github.com/AdiSuliman/uav-gcs-adaptive-secure-comms`), כולל `backup/v7-dev-smoke-stash-20261004`.
- **ריצות גרסה 7 נעצרו:** הלוגים של הריצה שנעצרה נמצאים ב-`C:\Users\Adi Suliman\uav-gcs-logs\interrupted_20261006\`.
- **גיבוי לכונן חיצוני** (אופציונלי, מומלץ): `docs\drive_swap\backup_to_external.ps1`. הגדלים מופיעים ב-`BACKUP_INVENTORY.md`, בערך 85 GB.

## 1. השיבוט
1. **התקנה פיזית:** מכבים, מתקינים את ה-990 PRO בחריץ ה-M.2 הפנוי, ומדליקים. Windows עולה מה-Kingston כרגיל.
2. **הכנת הכונן:** ב-Samsung Magician מעדכנים את הקושחה של ה-990 PRO. אחר כך: Data Migration, מקור Kingston, יעד 990 PRO. אם אפשר, לכלול גם את מחיצת D:.
3. **בוחרים כונן אתחול:** מאתחלים, נכנסים ל-BIOS (מקש Delete), ב-Boot Priority שמים את ה-990 PRO ראשון, שומרים ויוצאים.
4. **בודקים בסייר הקבצים:** ‏C: בגודל ~4 TB, כלומר המחשב עלה מהחדש. רושמים איזו אות קיבלה מחיצת D הישנה, למשל D: או E:.

## 2. בדיקות (בסדר הזה)
1. **Windows מופעל:** הגדרות ← מערכת ← הפעלה. אם לא, מקשרים לחשבון Microsoft. הרישיון הוא Retail.
2. **git:** בטרמינל (Git Bash):
   ```bash
   cd "/c/Users/Adi Suliman/uav-gcs-adaptive-secure-comms" && git status && git worktree list
   ```
   אם פרופיל 3 לא מופיע במקומו כי אות הכונן השתנתה:
   ```bash
   git worktree repair "/e/uav-gcs-v7-p3"
   ```
   (מחליפים את `/e/` באות שהתקבלה. **לא** להריץ `git worktree prune` לפני ה-repair.)
   אם מופיעה השגיאה "dubious ownership":
   ```bash
   git config --global --add safe.directory '*'
   ```
3. **MATLAB:** פותחים R2026a. אם מבקש הפעלה, מתחברים לחשבון MathWorks. אחר כך מריצים:
   ```matlab
   ver
   gpuDevice
   ```
   מצפים ל-116 מוצרים ול-RTX 4070 SUPER.
   אם במשתנה PATH מופיע `D:\Program Files\MATLAB\R2026a` (התקנה שנייה וישנה), כדאי להוציא אותו מה-PATH. **לא** למחוק את התיקייה.
4. **בדיקות היחידה של גרסה 7:**
   ```bash
   cd "/c/Users/Adi Suliman/uav-gcs-v7" && matlab -batch "startup; evalc('init_params'); r = runtests('code/tests/test_core.m'); fprintf('V7TESTS %d/%d\n', sum([r.Passed]), numel(r))"
   ```
   מצפים ל-`V7TESTS 73/73`.
5. **Python** (לכלי הדוח ולייצוא PDF):
   ```bash
   python -c "import pymupdf, lxml; print('ok')"
   ```

## 3. המשך גרסה 7 מאיפה שעצרנו
כל פרופיל ממשיך מהשלב הראשון שלא הסתיים. מה שהסתיים נשמר ב-`data\` וב-`results\` שלו.
- **פרופיל 1** (3 אנטנות, `C:\Users\Adi Suliman\uav-gcs-v7`): ממשיך מהשלב שנעצר. ראו סעיף 4.
- **פרופיל 3** (4 אנטנות, `D:\uav-gcs-v7-p3`, או האות החדשה): כנ"ל.
- **פרופיל 2** (2 אנטנות): יתחיל אוטומטית כשפרופיל 1 מסתיים.

הפקודה, מ-PowerShell. היא מפעילה את הריצה כתהליך עצמאי, כך שסגירת האפליקציה לא עוצרת אותה. אם פרופיל 3 קיבל אות אחרת, מחליפים את `/d/uav-gcs-v7-p3` בנתיב החדש בשורה:
```powershell
Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine='"C:\Program Files\Git\bin\bash.exe" -lc "bash ''/c/Users/Adi Suliman/uav-gcs-v7/docs/drive_swap/v7_resume.sh'' ''/d/uav-gcs-v7-p3'' > ''/c/Users/Adi Suliman/uav-gcs-logs/v7_resume.log'' 2>&1"'; CurrentDirectory='C:\Users\Adi Suliman\uav-gcs-v7'}
```
הסקריפט מריץ קודם את בדיקות היחידה, ורק אם כולן עוברות הוא ממשיך את הפרופילים.

**מעקב:** לוגים ב-`C:\Users\Adi Suliman\uav-gcs-logs\` (`v7_resume.log`, ‏`full_v7p1.log`, ‏`full_v7p3.log`).

## 4. איפה עצרנו (מתעדכן בעצירה)
ראו `STOP_STATUS.md` בתיקייה הזו.

## 5. אם השיבוט נכשל (התקנה נקייה)
- רשימת ההתקנה: `REINSTALL.md`.
- נתיבים קשיחים שצריך לעדכן: `HARDCODED_PATHS.md`. קוד הפרויקט עצמו נקי מנתיבים קשיחים. הנתיבים נמצאים רק בסקריפטי ההפעלה ובכלי הדוח.
- **לשמור על שם המשתמש ב-Windows: `Adi Suliman`.**
- את הקבצים מחזירים מהכונן הישן (מחובר כמשני) או מהגיבוי החיצוני. את הקוד אפשר גם לשכפל מ-GitHub.
