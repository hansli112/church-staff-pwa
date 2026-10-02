import json, urllib.request, sys
def c(action, **kw):
    kw['action']=action
    req=urllib.request.Request('http://127.0.0.1:9333', data=json.dumps(kw).encode(), method='POST')
    with urllib.request.urlopen(req, timeout=300) as r: return json.loads(r.read() or 'null')
def ev(expr): return c('eval', expression=expr)
def paste_html(html, text=''):
    return ev("""(() => { const ed=document.querySelector('.ContentEditable__root'); ed.focus();
      const dt=new DataTransfer(); dt.setData('text/html', %s); dt.setData('text/plain', %s);
      ed.dispatchEvent(new ClipboardEvent('paste', {clipboardData: dt, bubbles: true, cancelable: true})); return true; })()""" % (json.dumps(html), json.dumps(text or 'x')))
