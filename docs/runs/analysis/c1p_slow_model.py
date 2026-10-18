import heapq, itertools
SING=['jamming','noise_burst','reactive_jamming','path_loss','spoofing','antenna_fault','benign_interference','sweeping_jammer','tone_jamming','airframe_shadowing']
EMIT={'jamming','noise_burst','reactive_jamming','spoofing','benign_interference','sweeping_jammer','tone_jamming'}
NU={'jamming':24,'noise_burst':12,'reactive_jamming':24,'path_loss':12,'spoofing':24,'antenna_fault':12,'benign_interference':24,'sweeping_jammer':24,'tone_jamming':24,'airframe_shadowing':12}
COMB=['jamming+path_loss','noise_burst+antenna_fault','sweeping_jammer+path_loss','spoofing+noise_burst','reactive_jamming+path_loss','jamming+antenna_fault','spoofing+sweeping_jammer','benign_interference+noise_burst','jamming+airframe_shadowing','tone_jamming+path_loss','jamming+spoofing+benign_interference','noise_burst+spoofing+antenna_fault','jamming+airframe_shadowing+path_loss','tone_jamming+spoofing+airframe_shadowing']
cells=[('none',3,12,[(146,20),(404,38)])]
for t in SING:
    for v in range(1,6):
        if t=='airframe_shadowing': fl=[(86+(12 if v==3 else 0),38)]
        else: fl=[(110+(12 if v==3 else 0),20)]
        cells.append((t,v,NU[t],fl))
for t in COMB:
    for v in (2,3,4):
        fr=38 if 'airframe_shadowing' in t else 20
        cells.append((t,v,24,[(50,fr)]))
assert len(cells)==93
sims=sum(6*c[2]*sum(n for n,_ in c[3]) for c in cells); print('sims',sims)
seq=sum(6*c[2]*sum(n*f/20 for n,f in c[3]) for c in cells); print('20-frame sim-eq',round(seq),'x%.3f'%(seq/sims))
def cost(c,B0,E):
    ne=sum(1 for x in c[0].split('+') if x in EMIT)
    s=B0+E*ne
    return 6*c[2]*sum(n*f/20 for n,f in c[3])*s/3600  # worker-hours
def sched(B0,E,W=6,order=None,done=None):
    hrs=[cost(c,B0,E) for c in cells]
    idx=list(range(93)) if order is None else order
    heap=[0.0]*W; heapq.heapify(heap); fin=[]
    for i in idx:
        t=heapq.heappop(heap); heapq.heappush(heap,t+hrs[i]); fin.append(t+hrs[i])
    return sum(hrs), max(fin), hrs
for B0,E in [(1.71,1.27),(1.71*0.9,1.27*0.9),(1.71*1.1,1.27*1.15),(1.5,1.48)]:
    tot,mk,hrs=sched(B0,E)
    lpt=sorted(range(93),key=lambda i:-hrs[i]); _,mk2,_=sched(B0,E,order=lpt)
    _,mk7,_=sched(B0,E,W=7); _,mk7l,_=sched(B0,E,W=7,order=lpt)
    print('B0 %.2f E %.2f: worker-h %.0f, ideal/6 %.1f h, index-order makespan %.1f h, LPT %.1f h | 7 workers %.1f / LPT %.1f' % (B0,E,tot,tot/6,mk,mk2,mk7,mk7l))
tot,mk,hrs=sched(1.71,1.27)
print('cell1 none %.1f h; jamming nominal %.1f h; jamming other %.1f h; combos min %.1f max %.1f h' % (hrs[0],hrs[3],hrs[1],min(hrs[51:]),max(hrs[51:])))
# 7.10 check: cost same structure, old layout: none 146x20, shadow singles shared 110/122 at 20, combos 50 at 20
old=[]
for c in cells:
    if c[0]=='none': old.append(6*12*146)
    elif c[0]=='airframe_shadowing': old.append(6*12*(110+(12 if c[1]==3 else 0)))
    else: old.append(6*c[2]*sum(n for n,_ in c[3]))
print('7.10 layout sims',sum(old))
print('--- recalibrated from worker build timestamps')
for B0,E in [(1.75,1.08),(1.75,1.15),(1.75,1.23),(1.75,1.40)]:
    tot,mk,hrs=sched(B0,E)
    lpt=sorted(range(93),key=lambda i:-hrs[i]); _,mk2,_=sched(B0,E,order=lpt)
    _,mk7l,_=sched(B0,E,W=7,order=lpt)
    print('B0 %.2f E %.2f: worker-h %.0f ideal/6 %.1f index %.1f LPT %.1f 7w-LPT %.1f' % (B0,E,tot,tot/6,mk,mk2,mk7l))
# fec sharing: unique sims x(4/6) plus re-extraction of the shared third at fraction x of a sim
for x in (0.12,0.2,0.25):
    f=4/6+2/6*x
    tot,mk,hrs=sched(1.75,1.15)
    h2=[h*f for h in hrs]
    import heapq
    def mks(h,W,order):
        hp=[0.0]*W; heapq.heapify(hp); m=0
        for i in order:
            t=heapq.heappop(hp)+h[i]; heapq.heappush(hp,t); m=max(m,t)
        return m
    lpt=sorted(range(93),key=lambda i:-h2[i])
    print('fec share x=%.2f factor %.3f: worker-h %.0f, 6w LPT %.1f h, 7w LPT %.1f h' % (x,f,sum(h2),mks(h2,6,lpt),mks(h2,7,lpt)))
# remaining for live P1 at 8.9 h elapsed: done fraction
tot,mk,hrs=sched(1.75,1.15)
done=hrs[0]*3.5/12+sum(hrs[1:6])*16.4/24
print('P1 done worker-h at 12:20: %.0f of %.0f; remaining/6 = %.1f h' % (done,tot,(tot-done)/6))
