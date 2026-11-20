local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function distance(a,b)
  local r,g,bl = a.r-b.r,a.g-b.g,a.b-b.b
  return r*r*0.30+g*g*0.59+bl*bl*0.11
end

-- Deterministic weighted k-means: all colors come from the input; no model or network.
local function palette(pixels, count)
  local hist, colors = {}, {}
  for _,p in ipairs(pixels) do
    if p.a > 0 then
      local key = p.r*65536+p.g*256+p.b
      local c = hist[key]
      if c then c.n=c.n+1 else
        c={r=p.r,g=p.g,b=p.b,n=1}; hist[key]=c; colors[#colors+1]=c
      end
    end
  end
  if #colors == 0 then return {} end
  table.sort(colors,function(a,b) if a.n ~= b.n then return a.n>b.n end
    return a.r*65536+a.g*256+a.b < b.r*65536+b.g*256+b.b end)
  local centers={{r=colors[1].r,g=colors[1].g,b=colors[1].b}}
  while #centers < math.min(count,#colors) do
    local best,score=nil,-1
    for _,c in ipairs(colors) do
      local d=math.huge
      for _,q in ipairs(centers) do d=math.min(d,distance(c,q)) end
      local s=d*math.sqrt(c.n)
      if s>score then best,score=c,s end
    end
    if score<=0 then break end
    centers[#centers+1]={r=best.r,g=best.g,b=best.b}
  end
  for _=1,8 do
    local sums={}
    for i=1,#centers do sums[i]={r=0,g=0,b=0,n=0} end
    for _,c in ipairs(colors) do
      local bi,bd=1,math.huge
      for i,q in ipairs(centers) do local d=distance(c,q); if d<bd then bi,bd=i,d end end
      local s=sums[bi]; s.r=s.r+c.r*c.n; s.g=s.g+c.g*c.n; s.b=s.b+c.b*c.n; s.n=s.n+c.n
    end
    for i,s in ipairs(sums) do if s.n>0 then centers[i]={r=math.floor(s.r/s.n+0.5),g=math.floor(s.g/s.n+0.5),b=math.floor(s.b/s.n+0.5)} end end
  end
  return centers
end

local function run(opts)
  local sprite=app.activeSprite
  if not sprite then app.alert('Open an image or sprite first.'); return end
  local frame=app.activeFrame.frameNumber
  local src=Image(sprite.width,sprite.height,ColorMode.RGB)
  src:drawSprite(sprite,frame)
  local block=opts.block
  local w,h=math.ceil(sprite.width/block),math.ceil(sprite.height/block)
  local pixels={}
  for y=0,h-1 do
    for x=0,w-1 do
      local r,g,b,a,n=0,0,0,0,0
      for sy=y*block,math.min((y+1)*block-1,sprite.height-1) do
        for sx=x*block,math.min((x+1)*block-1,sprite.width-1) do
          local c=src:getPixel(sx,sy); local pc=app.pixelColor
          local alpha=pc.rgbaA(c)/255
          r=r+pc.rgbaR(c)*alpha; g=g+pc.rgbaG(c)*alpha; b=b+pc.rgbaB(c)*alpha; a=a+alpha; n=n+1
        end
      end
      -- The threshold removes translucent fringe pixels; transparent RGB cannot bleed.
      if a/n >= opts.alpha/100 and a>0 then
        pixels[#pixels+1]={r=math.floor(r/a+0.5),g=math.floor(g/a+0.5),b=math.floor(b/a+0.5),a=255}
      else pixels[#pixels+1]={r=0,g=0,b=0,a=0} end
    end
  end
  local count=opts.detail=='Base colors' and 4 or (opts.detail=='Simple shading' and 8 or 16)
  if opts.detail=='Custom palette' then count=opts.colors end
  local centers=palette(pixels,count)
  local pad=opts.outline and 1 or 0
  local result=Image(w+pad*2,h+pad*2,ColorMode.RGB)
  result:clear()
  if opts.outline then
    for y=0,h-1 do for x=0,w-1 do
      if pixels[y*w+x+1].a>0 then
        for _,d in ipairs({{-1,0},{1,0},{0,-1},{0,1}}) do
          local nx,ny=x+d[1],y+d[2]
          if nx<0 or nx>=w or ny<0 or ny>=h or pixels[ny*w+nx+1].a==0 then
            result:drawPixel(nx+pad,ny+pad,app.pixelColor.rgba(0,0,0,255))
          end
        end
      end
    end end
  end
  for y=0,h-1 do for x=0,w-1 do
    local p=pixels[y*w+x+1]
    if p.a>0 then
      local best,bd=centers[1],math.huge
      for _,c in ipairs(centers) do local d=distance(p,c); if d<bd then best,bd=c,d end end
      result:drawPixel(x+pad,y+pad,app.pixelColor.rgba(best.r,best.g,best.b,255))
    end
  end end
  local out=Sprite(result.width,result.height,ColorMode.RGB)
  app.transaction(function()
    local existing=out.layers[1]:cel(1)
    if existing then out:deleteCel(existing) end
    out:newCel(out.layers[1],1,result,Point(0,0))
  end)
  app.refresh()
end

local function showDialog()
  if not app.activeSprite then app.alert('Open an image or sprite first.'); return end
  local source=app.activeSprite
  local dlg=Dialog{title='Pixel Cleaner'}
  dlg:number{id='block',label='Input block size',text='4',decimals=0}
  dlg:combobox{id='detail',label='Color detail',option='Simple shading',options={'Base colors','Simple shading','Detailed shading','Custom palette'}}
  dlg:number{id='colors',label='Custom colors',text='12',decimals=0}
  dlg:check{id='outline',label='Black outline',text='Add outside silhouette',selected=false}
  dlg:slider{id='alpha',label='Opacity threshold',min=1,max=100,value=50}
  dlg:button{id='apply',text='Create sprite',onclick=function()
    local d=dlg.data
    if not d.block or d.block<1 or d.block>128 or not d.colors or d.colors<1 or d.colors>64 then
      app.alert('Block size must be 1–128 and custom colors 1–64.'); return
    end
    if app.activeSprite ~= source then
      app.alert("Select the original sprite again before creating the result."); return
    end
    dlg:close()
    local ok,err=pcall(run,{block=math.floor(d.block),detail=d.detail,colors=math.floor(d.colors),outline=d.outline,alpha=d.alpha})
    if not ok then app.alert('Pixel Cleaner: '..tostring(err)) end
  end}
  dlg:button{text='Cancel'}
  dlg:show{wait=false}
end
function init(plugin)
  plugin:newCommand{id='PixelCleaner',title='Pixel Cleaner',group='file_scripts',onclick=showDialog}
end
function exit(plugin) end
