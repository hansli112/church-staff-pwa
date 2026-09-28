import os, sys
TOOLS = os.path.dirname(os.path.abspath(__file__))
ARTICLE_DIR = os.path.dirname(TOOLS)
os.chdir(TOOLS); sys.path.insert(0, TOOLS)
# Rebuild the vocus article body from article.md and republish with current settings.
import sys, json, time, re; sys.path.insert(0,'.')
from vc import *
d=json.load(open('vocus-body.json')); imgs=json.load(open('vocus-images.json'))
missing=[n for n in d['caps'] if n not in imgs]
assert not missing, missing
for t in c('tabs'):
    if 'vocus.cc' in t['url']: c('close', targetId=t['targetId'])
c('open', url='https://vocus.cc/new-editor/6aba4b3afd89780001a439af'); time.sleep(12)
EMPTY='{"root":{"children":[{"children":[],"direction":null,"format":"","indent":0,"type":"paragraph","version":1}],"direction":null,"format":"","indent":0,"type":"root","version":1}}'
ev("(() => { const e=document.querySelector('.ContentEditable__root').__lexicalEditor; e.setEditorState(e.parseEditorState(%s)); return 1; })()" % json.dumps(EMPTY)); time.sleep(1)
r=ev("(() => { const p=document.querySelector('.ContentEditable__root p'); p.scrollIntoView({block:'center'}); const b=p.getBoundingClientRect(); return [b.x+5,b.y+b.height/2]; })()")
c('click', x=r[0], y=r[1]); time.sleep(1)
paste_html(d['html'],'x'); time.sleep(4)
state=json.loads(ev("(() => JSON.stringify(document.querySelector('.ContentEditable__root').__lexicalEditor.getEditorState().toJSON()))()"))
new=[]
for node in state['root']['children']:
    txt=''.join(x.get('text','') for x in node.get('children',[]) if isinstance(x,dict))
    if node.get('type')=='paragraph' and txt.startswith('@@IMG:') and txt.endswith('@@'):
        name=txt[6:-2]; im=imgs[name]
        new.append({"type":"image","version":1,"format":"","src":im['src'],"position":"center","width":im['width'],"height":im['height'],"source":None,"caption":d['caps'].get(name,''),"captionUrl":"","captionObj":{"root":{"children":[],"direction":None,"format":"","indent":0,"type":"root","version":1}}})
    else: new.append(node)
while len(new)>1 and new[-1].get('type')=='paragraph' and not new[-1].get('children') and new[-2].get('type')=='paragraph' and not new[-2].get('children'): new.pop()
if new and new[0].get('type')=='paragraph' and not new[0].get('children'): new.pop(0)
starts=[int(x) for x in re.findall(r'<ol start="(\d+)">', d['html'])]
ols=[x for x in new if x['type']=='list' and x.get('listType')=='number']
assert len(starts)==len(ols)
for x,s_ in zip(ols,starts):
    x['start']=s_
    for i,li in enumerate(x['children']): li['value']=s_+i
state['root']['children']=new
ev("(() => { const e=document.querySelector('.ContentEditable__root').__lexicalEditor; e.setEditorState(e.parseEditorState(%s)); return 1; })()" % json.dumps(json.dumps(state)))
time.sleep(3)
n_img=ev("(() => document.querySelectorAll('.ContentEditable__root img').length)()")
assert n_img==len(d['caps']) and not ev("(() => document.querySelector('.ContentEditable__root').innerText.includes('@@IMG'))()")
print('body ok', n_img, 'images')
time.sleep(5)
def btn(label):
    return ev("(() => { const b=[...document.querySelectorAll('button')].filter(b=>b.innerText.trim()===%r); if(!b.length) return null; b[b.length-1].click(); return b.length; })()" % label)
btn('調整發佈設定'); time.sleep(5)
btn('下一步'); time.sleep(3); ev("window.scrollTo(0,0)"); time.sleep(1)
if ev("document.body.innerText.includes('十架救恩')"): c('click', x=687, y=326); time.sleep(1)
assert not ev("document.body.innerText.includes('十架救恩')"), 'previous link still set'
btn('下一步'); time.sleep(3)
radios=dict(ev("(() => [...document.querySelectorAll('input[type=radio]')].map(r=>[r.value,r.checked]))()"))
assert radios.get('free') and radios.get('public'), radios
btn('確認發佈'); time.sleep(8)
print('published', ev("document.body.innerText.includes('發佈成功')"))
