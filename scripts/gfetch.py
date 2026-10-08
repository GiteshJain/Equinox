import urllib.request, http.cookiejar, sys, re
cj=http.cookiejar.CookieJar(); op=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
op.addheaders=[("User-Agent","Mozilla/5.0 (EquinoxPlanner weekly scan)")]
def get(url):
    with op.open(url, timeout=40) as r: return r.read().decode('utf-8','ignore')
if __name__=="__main__":
    s=get(sys.argv[1]); open(sys.argv[2],'w').write(s); print(len(s))
