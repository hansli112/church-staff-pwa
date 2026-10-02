import os, sys
TOOLS = os.path.dirname(os.path.abspath(__file__))
ARTICLE_DIR = os.path.dirname(TOOLS)
os.chdir(TOOLS); sys.path.insert(0, TOOLS)
import sys, base64, json, time, os, re; sys.path.insert(0,'.')
from vc import *
D=ARTICLE_DIR+'/'
names=re.findall(r'【插入圖 \d\d｜([^】]+)】', open(D+'article.md').read())
out={}
if os.path.exists('vocus-images.json'): out=json.load(open('vocus-images.json'))
STATE="JSON.stringify(document.querySelector('.ContentEditable__root').__lexicalEditor.getEditorState().toJSON().root.children.filter(n=>n.type==='image').map(n=>[n.src,n.width,n.height]))"
for name in names:
    if name in out: continue
    before=json.loads(ev("(() => %s)()" % STATE))
    b=base64.b64encode(open(D+'images/'+name,'rb').read()).decode()
    ev("""(() => { const ed=document.querySelector('.ContentEditable__root'); ed.focus();
      const bin=atob(%s); const u=new Uint8Array(bin.length); for(let i=0;i<bin.length;i++) u[i]=bin.charCodeAt(i);
      const dt=new DataTransfer(); dt.items.add(new File([u], %s, {type:'image/png'}));
      ed.dispatchEvent(new ClipboardEvent('paste', {clipboardData: dt, bubbles: true, cancelable: true})); return 1; })()""" % (json.dumps(b), json.dumps(name)))
    for _ in range(60):
        time.sleep(1)
        now=json.loads(ev("(() => %s)()" % STATE))
        new=[x for x in now if x not in before and x[0].startswith('https://images.vocus.cc/')]
        if new: break
    else:
        print('FAILED', name); break
    out[name]={'src':new[0][0],'width':new[0][1],'height':new[0][2]}
    json.dump(out, open('vocus-images.json','w'), indent=1)
    print(name, new[0][1], new[0][2], flush=True)
print(len(out), 'of', len(names))
