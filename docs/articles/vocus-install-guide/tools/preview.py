import os
os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # article dir
import re, base64, html
src=open('article.md').read().splitlines()
def inline(t):
    t=html.escape(t)
    t=re.sub(r'\*\*(.+?)\*\*',r'<strong>\1</strong>',t)
    t=re.sub(r'`(.+?)`',r'<code>\1</code>',t)
    t=re.sub(r'(https?://[^\s<）]+)',r'<a href="\1">\1</a>',t)
    return t
out=[]; i=0; lst=None
def close():
    global lst
    if lst: out.append(f'</{lst}>'); lst=None
while i<len(src):
    l=src[i]
    m=re.match(r'【插入圖 (\d\d)｜([^】]+)】',l)
    if m:
        close(); cap=''
        if i+1<len(src) and src[i+1].startswith('圖說：'): cap=src[i+1][3:]; i+=1
        b=base64.b64encode(open('images/'+m[2],'rb').read()).decode()
        out.append(f'<figure><div class="tag">圖 {m[1]} · images/{m[2]}</div><img src="data:image/png;base64,{b}" alt="{html.escape(cap)}"><figcaption>{inline(cap)}</figcaption></figure>')
    elif l.startswith('# '): close(); out.append(f'<h1>{inline(l[2:])}</h1>')
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
css='''body{margin:0;background:#f4f5f3;color:#1d2521;font:17px/1.8 -apple-system,"PingFang TC","Noto Sans TC",sans-serif}
main{max-width:760px;margin:0 auto;padding:32px 16px 80px;background:#fff}
.note{background:#fff7e0;border:1px solid #e8c96a;border-radius:8px;padding:12px 16px;font-size:15px;margin-bottom:24px}
h1{font-size:30px;line-height:1.35}h2{margin-top:44px;border-left:5px solid #1f6b4f;padding-left:12px}h3{margin-top:28px}
figure{margin:20px 0 28px}figure img{display:block;max-width:100%;margin:0 auto;border:1px solid #d9ddd9;border-radius:6px}
figcaption{font-size:14px;color:#5b655f;margin-top:6px;text-align:center}
.tag{font:12px/1.4 ui-monospace,Menlo,monospace;color:#8a4b00;background:#fff1dc;display:inline-block;padding:2px 8px;border-radius:4px;margin-bottom:6px}
blockquote{margin:16px 0;padding:10px 16px;background:#eef5f1;border-radius:6px}
code{background:#eef0ee;padding:1px 5px;border-radius:4px;font-size:.92em}hr{border:0;border-top:1px solid #e3e6e3;margin:36px 0}a{color:#1f6b4f}'''
page=f'''<!doctype html><html lang="zh-Hant"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>同工助手安裝教學預覽</title><style>{css}</style></head><body><main>
<div class="note">vocus 貼文預覽：文字可直接複製貼到 vocus 編輯器；橘色標籤處請上傳對應的 images/ 圖片，並把灰字圖說填進圖片說明。</div>
{"".join(out)}</main></body></html>'''
open('preview.html','w').write(page)
print(len(page)//1024,'KB')
