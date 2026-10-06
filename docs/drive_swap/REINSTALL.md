# התקנה מחדש אחרי החלפת כונן המערכת

נאסף ב-2026-10-06 ממצב המחשב הנוכחי (קריאה בלבד).

## 1. MATLAB

- **גרסה:** MATLAB **R2026a Update 2** (`26.1.0.3251617`, May 05 2026), מותקן ב-`C:\Program Files\MATLAB\R2026a`.
- יש עוד התקנה של R2026a Update 2 ב-`D:\Program Files\MATLAB\R2026a`, ושתיהן ב-PATH (C: קודם).
  אחרי ההחלפה האות של D: עלולה להשתנות: להסיר את `D:\Program Files\MATLAB\R2026a\bin` ו-`...\runtime\win64` מ-PATH
  ולהתקין עותק אחד בלבד על ה-SSD החדש.
- **רישוי:** חשבון MathWorks (התקנה מחדש דורשת התחברות והפעלה מחדש; הקבצים `matlabPkey.p12` ו-`thisMatlab.pem` ב-prefdir שייכים להפעלה הישנה).
- **העדפות:** לשחזר מהגיבוי `05_matlab_prefdir_R2026a` אל `%APPDATA%\MathWorks\MATLAB\R2026a` **לפני** ההפעלה הראשונה
  (או לתת ל-MATLAB לייבא). `Documents\MATLAB` ריק.

### מוצרים שהפרויקט צריך (חובה)
לפי `README.md` של v7 ושימוש בקוד:
- MATLAB, **Simulink**
- **Communications Toolbox** (`comm.*`, 46 קבצים)
- **DSP System Toolbox**, **Signal Processing Toolbox**
- **Deep Learning Toolbox** (`dlnetwork`; GPU דרך `canUseGPU`/`gpuDevice`)
- **Statistics and Machine Learning Toolbox**
- **Parallel Computing Toolbox** (`parpool`, מאגרי פריימים, GPU)
- **Antenna Toolbox** (77 קבצים מזכירים antenna), **RF Toolbox**, **Phased Array System Toolbox**
- **MATLAB Coder** (+ **GPU Coder** אם בונים MEX על GPU) - `codegen` ב-12 קבצים
- **Simulink 3D Animation** + **UAV Toolbox** (תצוגת 3D: `v3d_live`, `v3d_videos`, `sim3d`)
- **Reinforcement Learning Toolbox** (תוצאות DQN בענפים הישנים)
- **Support package:** *MATLAB Support for MinGW-w64 C/C++/Fortran Compiler* (מותקן ב-`C:\ProgramData\MATLAB\SupportPackages\R2026a`; נדרש ל-`codegen`/MEX)

### כל 116 המוצרים המותקנים כרגע (`C:\Program Files\MATLAB\R2026a\appdata\products`)
5G Toolbox; AUTOSAR Blockset; Aerospace Blockset; Aerospace Toolbox; Antenna Toolbox; Audio Toolbox; Automated Driving Toolbox;
Bioinformatics Toolbox; Bluetooth Toolbox; C2000 Microcontroller Blockset; Communications Toolbox; Computer Vision Toolbox;
Control System Toolbox; Curve Fitting Toolbox; DDS Blockset; DSP HDL Toolbox; DSP System Toolbox; Data Acquisition Toolbox;
Database Toolbox; Datafeed Toolbox; Deep Learning HDL Toolbox; Deep Learning Toolbox; Econometrics Toolbox; Embedded Coder;
Financial Instruments Toolbox; Financial Toolbox; Fixed-Point Designer; Fuzzy Logic Toolbox; GPU Coder; Global Optimization Toolbox;
HDL Coder; HDL Verifier; Image Acquisition Toolbox; Image Processing Toolbox; Industrial Communication Toolbox;
Instrument Control Toolbox; LTE Toolbox; Lidar Toolbox; MATLAB; MATLAB Coder; MATLAB Compiler; MATLAB Compiler SDK;
MATLAB Report Generator; MATLAB Test; Mapping Toolbox; Medical Imaging Toolbox; Mixed-Signal Blockset;
Model Predictive Control Toolbox; Model-Based Calibration Toolbox; Motor Control Blockset; Navigation Toolbox;
Optimization Toolbox; Parallel Computing Toolbox; Partial Differential Equation Toolbox; Phased Array System Toolbox;
Powertrain Blockset; Predictive Maintenance Toolbox; RF Blockset; RF PCB Toolbox; RF Toolbox; ROS Toolbox; Radar Toolbox;
Raspberry Pi Blockset; Reinforcement Learning Toolbox; Requirements Toolbox; Risk Management Toolbox;
Robotics System Toolbox; Robust Control Toolbox; STM32 Microcontroller Blockset; Satellite Communications Toolbox;
Sensor Fusion and Tracking Toolbox; SerDes Toolbox; Signal Integrity Toolbox; Signal Processing Toolbox; SimBiology;
SimEvents; Simscape; Simscape Battery; Simscape Driveline; Simscape Electrical; Simscape Fluids; Simscape Multibody;
Simulink; Simulink 3D Animation; Simulink Check; Simulink Code Inspector; Simulink Coder; Simulink Compiler;
Simulink Control Design; Simulink Coverage; Simulink Design Optimization; Simulink Design Verifier;
Simulink Desktop Real-Time; Simulink FMU Builder; Simulink Fault Analyzer; Simulink PLC Coder; Simulink Real-Time;
Simulink Report Generator; Simulink Test; SoC Blockset; Spreadsheet Link; Stateflow;
Statistics and Machine Learning Toolbox; Symbolic Math Toolbox; System Composer; System Identification Toolbox;
Text Analytics Toolbox; UAV Toolbox; Vehicle Dynamics Blockset; Vehicle Network Toolbox; Vision HDL Toolbox; WLAN Toolbox;
Wavelet Toolbox; Wireless HDL Toolbox; Wireless Network Toolbox; Wireless Testbench.

(אפשר להתקין שוב את כולן, או רק את רשימת החובה למעלה כדי לחסוך מקום.)

## 2. GPU

- **NVIDIA GeForce RTX 4070 SUPER**, דרייבר **616.56** (CUDA UMD 13.4 לפי `nvidia-smi`).
- Deep Learning Toolbox / Parallel Computing Toolbox מביאים את ספריות ה-CUDA בעצמם; **אין צורך ב-CUDA Toolkit נפרד**
  (גם עכשיו הוא לא מותקן). מספיק דרייבר NVIDIA עדכני (Game Ready או Studio, 616.56 ומעלה).
  GPU Coder בלבד עשוי לדרוש CUDA Toolkit אם בונים MEX ל-GPU.
- בדיקה אחרי ההתקנה: ב-MATLAB `gpuDevice` ו-`canUseGPU` צריכים להחזיר את ה-RTX 4070 SUPER.
- NVIDIA App 11.0.5.420 (אופציונלי).

## 3. Python

- **Python 3.11.9 (64-bit)** - זה ה-`python` שב-PATH (`C:\Users\Adi Suliman\AppData\Local\Programs\Python\Python311`). עם Python Launcher (`py`).
- מותקן גם Python 3.9.13 (לא בשימוש הפרויקט).
- חבילות שהסקריפטים משתמשים בהן בפועל (imports בקבצי `*.py` במאגרים, ב-scratchpad וב-`כלי הדוח`):
  - **`pymupdf`** (`import pymupdf` / `fitz`) - מותקן 1.28.2
  - **`lxml`** - מותקן 6.1.3
  - השאר ספרייה סטנדרטית: `io, os, re, sys, json, xml, zipfile, struct, shutil, math, datetime, subprocess, statistics, random, itertools, html, functools`.
  - `numpy` ו-`scipy` מיובאים בשני סקריפטי scratchpad אבל **לא מותקנים** כרגע; להתקין רק אם צריך אותם.
  - מודולים מקומיים (לא pip): `docxgen`, `docx_he`, `edit_util`, `hdoc`, `rep_*` - נמצאים ב-`כלי הדוח\` וב-scratchpad.
- התקנה:
  ```powershell
  winget install Python.Python.3.11
  py -3.11 -m pip install pymupdf==1.28.2 lxml==6.1.3
  ```

## 4. Node.js

- **Node.js v26.3.0** (`C:\Program Files\nodejs`). אין חבילות npm גלובליות.

## 5. Git ו-GitHub

- **Git for Windows 2.55.0.windows.5** (`C:\Program Files\Git`, כולל Git Bash שמריץ את המשגרים `*.sh`).
- `git config --global`:
  - `user.name = Adi Suliman`
  - `user.email = adisuliman999@gmail.com`
  - `core.editor = "C:\Users\Adi Suliman\AppData\Local\Programs\Microsoft VS Code\bin\code" --wait`
- **credential helper:** `manager` (Git Credential Manager, מוגדר ברמת system ע"י מתקין Git). הסיסמה/טוקן שמורים ב-Windows Credential Manager ולא יעברו - צריך להתחבר מחדש בדחיפה הראשונה.
- **GitHub CLI 2.101.0**, מחובר כ-`AdiSuliman` (keyring, פרוטוקול https). אחרי ההתקנה: `gh auth login`.
- **Remote:** `origin  https://github.com/AdiSuliman/uav-gcs-adaptive-secure-comms.git` (fetch ו-push).
- שחזור `.gitconfig` מהגיבוי (`07_user_root_files\.gitconfig`) או:
  ```powershell
  git config --global user.name "Adi Suliman"
  git config --global user.email "adisuliman999@gmail.com"
  git config --global core.editor "\"C:\Users\Adi Suliman\AppData\Local\Programs\Microsoft VS Code\bin\code\" --wait"
  ```

## 6. Office ו-PDF

- **Microsoft Office (Microsoft 365, Click-to-Run, Office16):** `C:\Program Files\Microsoft Office\root\Office16\WINWORD.EXE` (+ Excel, PowerPoint).
  Word משמש לייצוא PDF דרך COM (`docx2pdf.ps1`, `v6_summary\convert.ps1` ב-scratchpad: `Word.Application` -> `ExportAsFixedFormat`). צריך להפעיל את Word פעם אחת ידנית אחרי ההתקנה (רישוי/דיאלוג ראשון) לפני שה-COM עובד בשקט.
- גופן **David** (`C:\Windows\Fonts\david.ttf`) - בשימוש ב-`proposal_review\_x\wrap.py`; מגיע עם Windows בעברית / חבילת שפה עברית.
- **LibreOffice: לא מותקן.**

## 7. כלים נוספים שמותקנים כרגע

- Visual Studio Code 1.138.0 (User install), Visual Studio Community 2026 (18.1.1).
- אפליקציית Claude לשולחן העבודה (הגדרות ב-`%APPDATA%\Claude`, גיבוי `03_appdata_roaming_claude`), זיכרון וסשנים ב-`%USERPROFILE%\.claude` (גיבוי `02_dot_claude_memory_sessions`).

## 8. סדר מומלץ אחרי ההחלפה

1. Windows, דרייבר NVIDIA, Git, GitHub CLI (`gh auth login`), VS Code, Python 3.11 + pip, Node.js, Office.
2. **לשמור על אותו שם משתמש Windows** (`Adi Suliman`, כלומר `C:\Users\Adi Suliman`). אחרת כל הנתיבים ב-`HARDCODED_PATHS.md` וגם שם תיקיית הזיכרון של Claude (`C--Users-Adi-Suliman-...`) משתנים.
3. MATLAB R2026a Update 2 + המוצרים + MinGW support package; שחזור prefdir.
4. שחזור `.claude`, `%APPDATA%\Claude`, תיקיית הפרויקט בשולחן העבודה.
5. שחזור המאגר הראשי (כולל `.git`) וה-worktrees, ואז `git worktree repair` (ראו `HARDCODED_PATHS.md`).
6. בדיקה: `matlab -batch "ver"`, `gpuDevice`, `git -C <repo> worktree list`, `python -c "import pymupdf, lxml"`.
