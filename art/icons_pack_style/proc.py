import os,sys
from PIL import Image
H=os.path.dirname(os.path.abspath(__file__))
os.makedirs(H+'/out',exist_ok=True)
for f in sorted(os.listdir(H+'/raw')):
    im=Image.open(H+'/raw/'+f).convert('RGBA')
    a=im.getchannel('A').point(lambda v:255 if v>8 else 0)
    im=im.crop(a.getbbox())
    S,M=512,14
    k=(S-2*M)/max(im.size)
    im=im.resize((max(1,round(im.width*k)),max(1,round(im.height*k))),Image.LANCZOS)
    c=Image.new('RGBA',(S,S),(0,0,0,0)); c.paste(im,((S-im.width)//2,(S-im.height)//2),im)
    c.save(H+'/out/'+f)
fs=sorted(os.listdir(H+'/out')); n=len(fs); cols=9; rows=(n+cols-1)//cols
sheet=Image.new('RGBA',(cols*150,rows*170),(32,36,58,255))
from PIL import ImageDraw; d=ImageDraw.Draw(sheet)
for i,f in enumerate(fs):
    im=Image.open(H+'/out/'+f).resize((128,128),Image.LANCZOS); x,y=(i%cols)*150+11,(i//cols)*170+6
    sheet.paste(im,(x,y),im); d.text((x,y+134),f[:-4][:20],fill='white')
sheet.save(H+'/sheet.png'); print(n)
