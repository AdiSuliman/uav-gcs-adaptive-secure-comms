from datetime import datetime, timedelta
t0=datetime(2026,10,18,3,20)
def f(h): return (t0+timedelta(hours=h)).strftime('%d.%m %H:%M')
S={'low':dict(c1p=140,c1c=13,surv=3.5,surv3=4.9,dec=22,k3=1.10,k2=0.85,fin=1.5),
   'mid':dict(c1p=147,c1c=14,surv=4.5,surv3=6.5,dec=40,k3=1.15,k2=0.92,fin=2),
   'high':dict(c1p=165,c1c=15,surv=5.7,surv3=8.2,dec=52,k3=1.25,k2=1.00,fin=2)}
for spd in (False,True):
  print('=== speedups for P3/P2:',spd)
  for k,s in S.items():
    b1=s['c1p']+s['c1c']+s['surv']+s['surv3']
    if spd:
        sc=lambda c1p,c1c,sv: c1p*0.70*0.93+c1c*0.85*0.93+sv*0.72*0.93
    else:
        sc=lambda c1p,c1c,sv: c1p+c1c+sv
    b3=sc(s['c1p'],s['c1c'],s['surv']+s['surv3'])*s['k3']
    b2=sc(s['c1p'],s['c1c'],s['surv']+s['surv3'])*s['k2']
    e1c=s['c1p']; e1s=b1; e1=b1+s['dec']; e3s=b1+b3; e3=e3s+s['dec']; e2s=e3s+b2; e2=e2s+s['dec']; all_=e2+s['fin']
    print(f"{k:4s}: P1 C1p end {f(e1c)} | P1 SURV3 {f(e1s)} | P1 end {f(e1)} | P3 SURV3 {f(e3s)} | P3 end {f(e3)} | P2 end {f(e2)} | all {f(all_)}  (blocks P1 {b1:.0f} P3 {b3:.0f} P2 {b2:.0f} h; total {all_:.0f} h)")
