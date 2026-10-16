# נתיבים קשיחים - מה משתנה אחרי החלפת הכונן

**ההנחה:** ה-SSD החדש הופך ל-`C:` עם Windows נקי. הדיסק הישן (היום `C:` ו-`D:`) הופך לכונן משני, והאותיות
שלו יכולות להשתנות (למשל `E:` ו-`F:`). לכן כל מה שב-`D:\` זז, וכל מה שב-`C:\` קיים רק אם משחזרים אותו לאותו נתיב.
**המלצה מרכזית:** לשמור את שם המשתמש `Adi Suliman` ולשחזר את המאגרים לאותם נתיבים תחת `C:\Users\Adi Suliman\`.
אז כמעט כל הנתיבים למטה נשארים תקינים, וחוץ מ-Temp ו-`D:` לא צריך לשנות כלום.

נסרק (grep, 2026-10-06): `*.m, *.sh, *.ps1, *.json, *.py, *.bat, *.cmd` בכל ה-worktrees (בלי `data\`, `archive\`, `slprj\`, `results\`, `.git\`),
`.claude\*.json`, `profile.json`, `C:\Users\Adi Suliman\.claude\settings.json`, ה-scratchpad של הסשן, ו-`כלי הדוח` בתיקיית הפרויקט בשולחן העבודה.
תבניות: `C:\`, `C:/`, `/c/`, `D:\`, `D:/`, `/d/`, `Users/Adi Suliman`, `ADISUL~1`, `AppData\Local\Temp`, `tempdir`.

## 1. קוד הפרויקט במאגרים - נקי

**אין אף נתיב מוחלט** בקוד (`code\**\*.m`), ב-`startup.m`, ב-`profile.json` או ב-`.claude\*.json` של אף worktree.
ההופעות היחידות הן `tempdir`, שמחושב בזמן ריצה ולכן עובר אוטומטית ל-Temp של ה-SSD החדש:

| קובץ:שורה (זהה בכל ה-worktrees) | שימוש | משתנה? | מה לעשות |
|---|---|---|---|
| `code\decision\pool_worker_init.m:6` | `fullfile(tempdir, 'uavgcs_worker_<pid>')` | לא (יחסי) | כלום |
| `code\parallel_turn.m:8` | `fullfile(tempdir, 'uav_gcs_parallel_turn.txt')` (תור בין ריצות מקבילות) | לא | כלום |
| `code\disk_guard.m:23-30` | בודק מקום פנוי בכונן של `tempdir` ו-`.dmr` ב-`tempdir`; `MIN_FREE_GB = 150` (שורה 12), `MAX_DMR_GB = 2` | לא, אבל **התנאי עובר ל-SSD החדש** | ה-SSD החדש חייב להשאיר **≥150 GB פנויים** ב-`C:`, אחרת כל ריצה נעצרת עם `disk_guard:space` |
| `code\dev\dev_*.m` (v7, v7-merge, v7-p3: `dev_adc_backoff:9, dev_dump:47, dev_erasure_threshold:7, dev_eval_rx:7, dev_fec_flights:11, dev_fec_table:11, dev_monitor_window:15, dev_noise_floor:11, dev_rx_script:5, dev_setup:9, dev_sync_threshold:13`) | ברירת מחדל `fullfile(tempdir, 'uav_gcs_dev')` | לא | כלום (תוצרי dev זמניים ייעלמו) |

## 2. ה-scratchpad (תלוי ב-Temp - הסיכון הגדול)

כל ה-scratchpad נמצא ב-`C:\Users\ADISUL~1\AppData\Local\Temp\claude\C--Users-Adi-Suliman-uav-gcs-adaptive-secure-comms\0ff3360f-912b-4701-bfb0-77d6917b5fc3\scratchpad`.
אחרי ההחלפה התיקייה הזו לא קיימת ב-`C:` החדש. בנוסף `ADISUL~1` הוא שם 8.3 קצר שלא מובטח שיהיה זהה (או קיים) בהתקנה חדשה.
229 קבצים ב-scratchpad מכילים נתיב מוחלט. הסקריפטים החשובים:

| קובץ:שורה | נתיב | משתנה? | מה לעדכן |
|---|---|---|---|
| `v7_launcher_v2.sh:6` (**רץ עכשיו**) | `S=/c/Users/ADISUL~1/AppData/Local/Temp/claude/.../scratchpad` | **כן** | להעביר את ה-scratchpad לתיקייה קבועה (למשל `C:\Users\Adi Suliman\uav_work\scratchpad`) ולעדכן `S` |
| `v7_launcher_v2.sh:7` | `V7=/c/Users/Adi Suliman/uav-gcs-v7` | לא, אם משחזרים לאותו נתיב | - |
| `v7_launcher_v2.sh:26` | `P3=/d/uav-gcs-v7-p3` | **כן** (`D:` זז) | לאות החדשה של הדיסק הישן, או להעביר את p3 ל-`C:\Users\Adi Suliman\uav-gcs-v7-p3` אם יש מקום (זכור `disk_guard`: ≥150 GB פנויים) |
| `v7_launcher_v2.sh:33` | `P2=/d/uav-gcs-v7-p2` (נוצר ע"י המשגר אחרי פרופיל 1; עוד לא קיים) | **כן** | כמו p3 |
| `v7_launcher_v2.sh:46` | `export_gui_bundle('C:/Users/Adi Suliman/uav-gcs-v7/profiles')` | לא, אם אותו נתיב | - |
| `v7_launcher.sh:5-6`, `v7_launcher_v1_full.sh:5-6,13,25,37,55` | `S=...Temp...`, `V7=`, `/c/Users/Adi Suliman/uav-gcs-v6`, `-v6-p2`, `uav-gcs-v7-p3`, `uav-gcs-v7-p2` | `S` כן | גרסאות ישנות; לעדכן רק אם מריצים שוב |
| `resume_v6.sh:4,6,8` | `S=...Temp...`, `/c/Users/Adi Suliman/uav-gcs-v6`, `uav-gcs-v6-p2` | `S` כן | כמו למעלה |
| `watch_next.sh:3` | `S=...Temp...` | כן | כמו למעלה |
| `build_report.py:26` (גם ב-`כלי הדוח`) | `C:/Users/Adi Suliman/Desktop/תואר ראשון  הנדסת חשמל ואלקטרוניקה/שנה ד/פרוייקט גמר/` | לא, אם אותו משתמש ו-Desktop לא מועבר ל-OneDrive | - |
| `prop_*.py`, `rep_*.py`, `dia_v5.py`, `docx_outline.py`, `e_figs.py`, `figs_ant.py`, `fill_results.py`, `fix_diag.py`, `ir_outline.py` (שורות 1-6) | נתיבי Desktop (`...\פרוייקט גמר\...`, `תמונות לדוח\...`) | לא, אם אותו משתמש | - |
| `codegen_debug_v7\mex\rxdbg\SetEnv.bat:1-4`, `rxdbg_mex.bat:3-4` | `C:\Program Files\MATLAB\R2026a\...`, `C:\ProgramData\MATLAB\SupportPackages\R2026a\3P.instrset\mingw_w64.instrset\...` | לא, אם MATLAB ו-MinGW מותקנים בברירת המחדל | נוצרים מחדש ע"י `codegen`; אפשר להתעלם |
| `proposal_review\_x\wrap.py:29` | `C:/Windows/Fonts/david.ttf` | לא | גופן David צריך להיות מותקן |
| `docx2pdf.ps1`, `v6_summary\convert.ps1` | אין נתיב קשיח (מקבלים `-In`/`-Out`); משתמשים ב-Word COM | לא | Word צריך להיות מותקן ומופעל פעם אחת |
| סקריפטי בדיקה חד-פעמיים (`*.m`: `cc_run.m`, `runv*.m`, `devsmoke.m`, `gui_check.m`, `v5_check.m`, `timing.m`...; `*.py`: `integrate_*.py`, `fix_ch5a.py`, `fill_d75.py`...) | `C:\Users\ADISUL~1\AppData\Local\Temp\...`, `C:\Users\Adi Suliman\uav-gcs-*` | Temp כן | לעדכן רק מה שמריצים שוב |

## 3. כלי הדוח בתיקיית הפרויקט בשולחן העבודה

`C:\Users\Adi Suliman\Desktop\תואר ראשון  הנדסת חשמל ואלקטרוניקה\שנה ד\פרוייקט גמר\כלי הדוח\`:

| קובץ:שורה | נתיב | משתנה? | מה לעדכן |
|---|---|---|---|
| `rep_3ant.py:3`, `rep_d69.py:3`, `rep_env.py:2` | `S = 'C:/Users/ADISUL~1/AppData/Local/Temp/claude/.../scratchpad/'` | **כן** | לתיקיית ה-scratchpad הקבועה החדשה |
| `rep_budget50.py:2` | `.../scratchpad/rep_ch4.py` (Temp) | **כן** | כנ"ל |
| `rep_ch4.py:163` | ברירת מחדל ל-`gui_png` ב-Temp scratchpad | **כן** | כנ"ל |
| `gui_check.m:5` | `out = 'C:\Users\ADISUL~1\AppData\Local\Temp\...\scratchpad\gui_check'` | **כן** | כנ"ל |
| `rep_ch3.py:6`, `rep_ch4.py:51`, `rep_ch5.py:5`, `rep_numbers.py:9` | `C:/Users/Adi Suliman/uav-gcs-adaptive-secure-comms/results/...` | לא, אם אותו נתיב | - |
| `rep_ch6.py:6` | `C:/Users/Adi Suliman/uav-gcs-adaptive-secure-comms/profile2_2antennas/results/` | לא, אם אותו נתיב | - |
| `build_report.py:26`, `dia_v5.py:3`, `rep_3ant.py:4`, `rep_ch3.py:5`, `rep_ch4.py:5`, `rep_d69.py:48` | נתיבי Desktop של הפרויקט | לא, אם אותו משתמש | - |

## 4. תצורה מחוץ למאגרים

| מקום | מה | משתנה? | מה לעשות |
|---|---|---|---|
| `C:\Users\Adi Suliman\.claude\settings.json` | אין נתיבים מוחלטים | לא | לשחזר כמו שהוא |
| `C:\Users\Adi Suliman\.claude\projects\C--Users-Adi-Suliman-uav-gcs-adaptive-secure-comms\` | שם התיקייה נגזר מנתיב המאגר | לא, אם המאגר חוזר ל-`C:\Users\Adi Suliman\uav-gcs-adaptive-secure-comms` | אם הנתיב משתנה, הזיכרון לא ייטען אוטומטית: לשנות את שם התיקייה לנתיב החדש |
| `C:\Users\Adi Suliman\.gitconfig` | `core.editor = "C:\Users\Adi Suliman\AppData\Local\Programs\Microsoft VS Code\bin\code" --wait` | לא, אם VS Code מותקן user-install | - |
| PATH של המערכת | `C:\Program Files\MATLAB\R2026a\bin`, **`D:\Program Files\MATLAB\R2026a\bin`** ו-`...\runtime\win64` | **D: כן** | להסיר את רשומות `D:\Program Files\MATLAB` מ-PATH |
| `%APPDATA%\MathWorks\MATLAB\R2026a\bookmarks.xml`, `MATLAB_Editor_State.xml`, `run_commands.m` | מזכירים תיקיות `uav-gcs-*` | רק ל-p3 (`D:`) | קוסמטי (מועדפים וקבצים פתוחים) |

## 5. מטא-דאטה של git worktree (חשוב)

כל ה-worktrees חולקים את מאגר האובייקטים היחיד ב-`C:\Users\Adi Suliman\uav-gcs-adaptive-secure-comms\.git`.
הקישור דו-כיווני ובנתיבים מוחלטים:

- בכל worktree יש **קובץ** `.git` עם שורה אחת, למשל
  `D:\uav-gcs-v7-p3\.git` -> `gitdir: C:/Users/Adi Suliman/uav-gcs-adaptive-secure-comms/.git/worktrees/uav-gcs-v7-p3`
- במאגר הראשי, `.git\worktrees\<name>\gitdir` מצביע חזרה, למשל
  `.git\worktrees\uav-gcs-v7-p3\gitdir` -> `D:/uav-gcs-v7-p3/.git`

worktrees רשומים (11): `profile2_2antennas`, `.claude\worktrees\agent-a4155c8f6df2f2640` (v7-docs), `.claude\worktrees\agent-a6d8443cbbbcfaf07` (v7-adversary),
`uav-gcs-v6`, `uav-gcs-v6-p2`, `uav-gcs-v7`, `uav-gcs-v7-g4rx`, `uav-gcs-v7-gaps`, `uav-gcs-v7-gapsB`, `uav-gcs-v7-merge`, `D:/uav-gcs-v7-p3`.

**אחרי ההעברה:**
1. לשחזר קודם את המאגר הראשי **כולל `.git\`** לאותו נתיב.
2. **לא להריץ `git worktree prune`** לפני התיקון: הוא ימחק את הרישום של worktrees שנראים חסרים (למשל p3 כש-`D:` השתנה).
3. מתוך המאגר הראשי, לתת ל-git את הנתיבים החדשים של כל worktree שזז (מתקן את שני הכיוונים):
   ```powershell
   cd "C:\Users\Adi Suliman\uav-gcs-adaptive-secure-comms"
   git worktree repair "E:/uav-gcs-v7-p3"          # האות החדשה, או הנתיב שאליו העברת
   git worktree list                               # לוודא שאין "prunable"
   ```
   אם כל ה-worktrees שוחזרו לאותם נתיבים, `git worktree repair` בלי ארגומנטים מספיק (או לא נדרש בכלל).
   אם גם המאגר הראשי זז: להריץ `git worktree repair <path1> <path2> ...` מתוך המיקום החדש שלו עם כל הנתיבים.
4. **בעלות על קבצים בדיסק הישן:** worktree שנשאר על הדיסק הישן שייך ל-SID של המשתמש הישן, ו-git יסרב
   (`detected dubious ownership`). פתרון: `git config --global --add safe.directory "E:/uav-gcs-v7-p3"` (לכל worktree כזה),
   או להעביר את התיקייה ל-SSD. קבצים שמשוחזרים מהגיבוי (robocopy `/COPY:DAT`, בלי בעלים) יהיו בבעלות המשתמש החדש ולא יציגו את הבעיה.
5. ה-stash (`stash@{0}`) נמצא ב-`.git` הראשי; הוא עובר יחד איתו.
