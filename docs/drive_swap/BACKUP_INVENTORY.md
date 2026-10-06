# מלאי גיבוי לפני החלפת כונן המערכת (2026-10-06)

נמדד ב-19:15–19:20 (PowerShell `Get-ChildItem -Recurse -File -Force | Measure-Object Length -Sum`).
הגדלים משתנים בזמן שהריצות פעילות (שתי ריצות MATLAB של v7: פרופיל 1 ב-`C:\Users\Adi Suliman\uav-gcs-v7`
ופרופיל 3 ב-`D:\uav-gcs-v7-p3`, מופעלות על ידי `v7_launcher_v2.sh` מתוך ה-scratchpad).

סקריפט הגיבוי: `backup_to_external.ps1` (באותה תיקייה). מעתיק בלבד, לפי סדר עדיפות, בלי מחיקה.

```powershell
# בדיקה יבשה (לא מעתיק כלום)
powershell -ExecutionPolicy Bypass -File "C:\Users\Adi Suliman\uav-gcs-v7\docs\drive_swap\backup_to_external.ps1" -Dest 'E:\uav_backup_20261006' -WhatIf
# גיבוי מלא
powershell -ExecutionPolicy Bypass -File "C:\Users\Adi Suliman\uav-gcs-v7\docs\drive_swap\backup_to_external.ps1" -Dest 'E:\uav_backup_20261006'
# רק הפריטים שאין להם תחליף, אם הזמן קצר (~11 GB)
powershell -ExecutionPolicy Bypass -File "...\backup_to_external.ps1" -Dest 'E:\uav_backup_20261006' -Only temp_claude,dot_claude,appdata_claude,desktop_project,matlab_prefs,git_config
```

## סיכום

| | גודל |
|---|---|
| **סה"כ לגיבוי מלא** | **~81.5 GB** (כ-102,000 קבצים) |
| מתוכם מאגרי נתונים (`data\`) | ~58.7 GB |
| מתוכם מטמון Simulink (`slprj\`, נבנה מחדש, אפשר לדלג עם `-SkipCaches`) | ~1.8 GB |
| פריטים שאין להם שום עותק אחר (scratchpad, `.claude`, Desktop, העדפות MATLAB) | ~10.9 GB |

הכונן החיצוני צריך לפחות ~85 GB פנויים.
הערה: הדיסק הישן לא נמחק בהחלפה (הוא הופך לכונן משני), אז זה גיבוי ביטוח. הסכנה האמיתית היא
אם הדיסק הישן יפורמט, או שתיקיית Temp תנוקה.

## הפריטים, לפי סדר עדיפות

סימון "ב-GitHub": האם התוכן נמצא גם ב-`https://github.com/AdiSuliman/uav-gcs-adaptive-secure-comms`.

| # | מפתח בסקריפט | נתיב | גודל | קבצים | ב-GitHub? | הערה |
|---|---|---|---|---|---|---|
| 1 | `temp_claude` | `C:\Users\Adi Suliman\AppData\Local\Temp\claude` | 8.35 GB | 16,438 | לא | **קריטי.** כולל את ה-scratchpad של הסשן `...\C--Users-Adi-Suliman-uav-gcs-adaptive-secure-comms\0ff3360f-912b-4701-bfb0-77d6917b5fc3\` (7.84 GB): כל לוגי הריצות (`full_v7p1.log`, `full_v7p3.log`, `v7_launcher_v2.log`...), המשגרים (`v7_launcher_v2.sh`, `resume_v6.sh`), מחקרים (`d74.md`, `d80.md`...), סקריפטי בניית ההצעה והדוח (`prop_*.py`, `rep_*.py`, `docx2pdf.ps1`), `v6_summary\`, `proposal_review\`, `tasks\` (פלט משימות רקע). Temp עלול לא לשרוד |
| 2 | `dot_claude` | `C:\Users\Adi Suliman\.claude` | 0.94 GB | 2,046 | לא | **קריטי.** `projects\C--Users-Adi-Suliman-uav-gcs-adaptive-secure-comms\memory\` (הזיכרון), תמלולי הסשנים (`projects\...\*.jsonl`), `settings.json`, `skills\`, `plugins\`, `file-history\` |
| 3 | `appdata_claude` | `C:\Users\Adi Suliman\AppData\Roaming\Claude` | 0.78 GB | 9,668 | לא | הגדרות אפליקציית Claude לשולחן העבודה וסביבות scratch |
| 4 | `desktop_project` | `C:\Users\Adi Suliman\Desktop\תואר ראשון  הנדסת חשמל ואלקטרוניקה\שנה ד\פרוייקט גמר` | 0.71 GB | 299 | לא | **קריטי.** הצעות, דוחות, ספריית המקורות, `כלי הדוח\` (build_report.py וכו'), `תמונות לדוח\`. שים לב: שני רווחים אחרי "תואר ראשון" |
| 5 | `matlab_prefs` | `C:\Users\Adi Suliman\AppData\Roaming\MathWorks\MATLAB\R2026a` (prefdir) | 0.11 GB | 8,883 | לא | העדפות, היסטוריית פקודות, קיצורים, מצב העורך |
| 6 | `matlab_docs` | `C:\Users\Adi Suliman\Documents\MATLAB` | 0 GB | 0 | - | ריקה; נכלל ליתר ביטחון |
| 7 | `git_config` | `C:\Users\Adi Suliman\.gitconfig` (+ `.bashrc`, `.bash_profile`, `.bash_history` אם קיימים) | <1 MB | 2 | לא | user.name/email, core.editor |
| 8 | `main_repo` | `C:\Users\Adi Suliman\uav-gcs-adaptive-secure-comms` | 29.46 GB | 11,054 | חלקית | ראו פירוט למטה. כולל את `.git\` (מאגר האובייקטים של **כל** ה-worktrees, כולל stash), `profile2_2antennas\` ו-`.claude\worktrees\*` |
| 9 | `v7` | `C:\Users\Adi Suliman\uav-gcs-v7` | 15.89 GB | 3,776 | חלקית | ריצת פרופיל 1 פעילה כאן |
| 10 | `v7_p3` | `D:\uav-gcs-v7-p3` | 0.09 GB | 879 | חלקית | ריצת פרופיל 3 פעילה כאן; `data\` עדיין ריק (0 קבצים) בזמן המדידה, יגדל |
| 11 | `v7_p2` | `D:\uav-gcs-v7-p2` | - | - | - | עוד לא קיים; המשגר ייצור אותו אחרי סיום פרופיל 1. הסקריפט מדלג אם חסר |
| 12 | `v7_merge` | `C:\Users\Adi Suliman\uav-gcs-v7-merge` | 1.11 GB | 1,739 | חלקית | |
| 13 | `v7_gaps` | `C:\Users\Adi Suliman\uav-gcs-v7-gaps` | 0.01 GB | 299 | כמעט כולו | קובץ אחד לא מקומיט |
| 14 | `v7_gapsB` | `C:\Users\Adi Suliman\uav-gcs-v7-gapsB` | 0.01 GB | 292 | כן | נקי |
| 15 | `v7_g4rx` | `C:\Users\Adi Suliman\uav-gcs-v7-g4rx` | 0.01 GB | 301 | כמעט כולו | קובץ אחד לא מקומיט |
| 16 | `v6` | `C:\Users\Adi Suliman\uav-gcs-v6` | 12.09 GB | 2,516 | חלקית | |
| 17 | `v6_p2` | `C:\Users\Adi Suliman\uav-gcs-v6-p2` | 11.94 GB | 1,108 | חלקית | |

סה"כ: 8.35 + 0.94 + 0.78 + 0.71 + 0.11 + 29.46 + 15.89 + 0.09 + 1.11 + 0.03 + 12.09 + 11.94 = **~81.5 GB**.

## פירוט תת-תיקיות ב-worktrees (GB)

| worktree | `data\` | `archive\` | `results\` | `logs\` | `slprj\` | `models\` | אחר |
|---|---|---|---|---|---|---|---|
| `uav-gcs-adaptive-secure-comms` (ללא profile2) | 11.131 | 7.280 | 0.411 | 0.010 | 0.862 | 0.000 | `GUI_Results\` 0.088, `ZIP files\` 0.021, `.git\` 0.025, `.claude\` 0.023 (כולל `worktrees\agent-*`) |
| `...\profile2_2antennas` | 9.532 | - | 0.005 | 0.004 | 0.062 | 0.000 | |
| `uav-gcs-v6` | 11.896 | - | 0.014 | 0.006 | 0.169 | 0.000 | |
| `uav-gcs-v6-p2` | 11.854 | - | 0.015 | 0.006 | 0.066 | 0.000 | |
| `uav-gcs-v7` | 13.351 | 1.987 | 0.009 | 0.005 | 0.396 | 0.000 | `profiles\` 0.137 (חבילות GUI) |
| `uav-gcs-v7-merge` | 0.915 | - | 0.007 | 0.005 | 0.183 | 0.000 | |
| `D:\uav-gcs-v7-p3` | 0.000 | - | 0.005 | 0.004 | 0.077 | 0.000 | `params.mat`, `profile.json` |
| `uav-gcs-v7-gaps` / `gapsB` / `g4rx` | - | - | 0.005 | 0.004 | - | 0.000 | |

`code\` ו-`docs\` הם ~1 MB בכל worktree.

## מה כבר ב-GitHub ומה באמת אין לו תחליף

**ב-GitHub (ניתן לשחזר ב-`git clone` + `git worktree add`):**
- כל הקוד (`code\**\*.m`), `docs\`, `startup.m`, `profile.json`, `README.md`.
- כל הענפים: `main`, `profile-2-antennas`, `profile-3-antennas`, `receiver-metrics-v4`, `v6-dev`, `v6-p2`,
  `v7-dev`, `v7-merge`, `v7-p3`, `v7-adversary`, `viz3d-unreal`. לענפים `v7-gaps`, `v7-gapsB`, `v7-g4rx`,
  `v7-docs` אין upstream, אבל כל הקומיטים שלהם כבר בתוך `v7-dev` (0 קומיטים לפני `v7-dev`), כלומר הם ב-GitHub.
- חלק מתוצאות ה-commit: בענפים יש `results\` (58–59 קבצים), `logs\` (26), `models\` (3), `params.mat` שמקומטים.

**לא ב-GitHub, אין לו תחליף (או שחזורו לוקח ימים של ריצה):**
- `data\` בכל worktree: מאגרי האימון והמודלים המאומנים (~58.7 GB). ב-`.gitignore`.
- `archive\` (גיבויי v3 ו-v6, 7.28 + 1.99 GB) - לפי ההנחיה, נשמרים עד אישור מפורש למחוק.
- `results\` ו-`logs\` העדכניים (השינויים שלא קומטו: 30 קבצים ב-main, 5 ב-v7, 4 ב-p3, 28 ב-v6 ו-v6-p2, 28 ב-v7-merge, 14 ב-profile2).
- `GUI_Results\`, `ZIP files\`, `v7\profiles\`.
- `stash@{0}` ב-`.git` של המאגר הראשי ("smoke outputs of 2026-10-04... before fast-forward to v7-merge") - קיים רק מקומית.
- כל ה-scratchpad (לוגים, משגרים, מחקרים, סקריפטי ההצעה והדוח), `.claude` (זיכרון ותמלולים), תיקיית הפרויקט בשולחן העבודה, העדפות MATLAB.

## הערות להפעלה
- להריץ קודם `-WhatIf` ולוודא שאין שגיאות נתיב. אחר כך להריץ מלא.
- הריצות הפעילות כותבות לקבצים בזמן ההעתקה: קבצים פתוחים יועתקו במצבם הנוכחי (או ידולגו עם שגיאה אחרי ניסיון אחד).
  אם הריצות מסתיימות או נעצרות לפני 20:30, להריץ את הסקריפט שוב: robocopy מעתיק רק קבצים שהשתנו.
- קודי יציאה של robocopy: 0–7 תקין, 8 ומעלה שגיאה. הלוג נשמר ב-`<Dest>\_logs\`.
- אין בסקריפט `/MIR`, `/MOV`, `/MOVE` או `/PURGE`. שום דבר לא נמחק במקור או ביעד.
- הסקריפט שמור ב-UTF-8 עם BOM כדי ש-Windows PowerShell 5.1 יקרא נכון את הנתיב בעברית. אם עורכים אותו, לשמור באותו קידוד.
