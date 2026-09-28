import os, sys
TOOLS = os.path.dirname(os.path.abspath(__file__))
ARTICLE_DIR = os.path.dirname(TOOLS)
os.chdir(TOOLS); sys.path.insert(0, TOOLS)
import re, base64, html
src=open(os.path.join(ARTICLE_DIR,'article.md')).read().splitlines()
def inline(t):
    t=html.escape(t)
    t=re.sub(r'\*\*(.+?)\*\*',r'<strong>\1</strong>',t)
    t=re.sub(r'`(.+?)`',r'<code>\1</code>',t)
    t=re.sub(r'(https?://[^\s<）]+)',r'<a href="\1">\1</a>',t)
    return t
out=[]; i=0; lst=None; caps={}
def close():
    global lst
    if lst: out.append(f'</{lst}>'); lst=None
while i<len(src):
    l=src[i]
    m=re.match(r'【插入圖 (\d\d)｜([^】]+)】',l)
    if m:
        close(); cap=''
        if i+1<len(src) and src[i+1].startswith('圖說：'): cap=src[i+1][3:]; i+=1
        caps[m[2]]=re.sub(r'\*\*(.+?)\*\*',r'\1',cap)
        out.append(f'<p>@@IMG:{m[2]}@@</p>')
    elif l.startswith('# '): close(); title=l[2:]
    elif l.startswith('## '): close(); out.append(f'<h2>{inline(l[3:])}</h2>')
    elif l.startswith('### '): close(); out.append(f'<h3>{inline(l[4:])}</h3>')
    elif l.strip()=='---': close(); out.append('<hr>')
    elif l.startswith('> '): close(); out.append(f'<blockquote>{inline(l[2:])}</blockquote>')
    elif re.match(r'- ',l):
        if lst!='ul': close(); out.append('<ul>'); lst='ul'
        out.append(f'<li>{inline(l[2:])}</li>')
    elif re.match(r'\d+\. ',l):
        if lst!='ol': close(); out.append(f'<ol start="{re.match(r"\d+",l)[0]}">'); lst='ol'
        out.append(f'<li>{inline(re.sub(r"^\d+\. ","",l))}</li>')
    elif l.strip()=='': 
        if lst and i+1<len(src) and (re.match(r'\d+\. |- ',src[i+1])): pass
        else: close()
    else: close(); out.append(f'<p>{inline(l)}</p>')
    i+=1
close()

import json
json.dump({'title':title,'html':''.join(out),'caps':caps},open('vocus-body.json','w'),ensure_ascii=False)
print(title, len(caps))
