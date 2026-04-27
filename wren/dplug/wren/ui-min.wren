class UI{
foreign static width
foreign static height
foreign static defaultWidth
foreign static defaultHeight
static root{
return UIElement.new("__ROOT__")
}
static getElementById(a){
return $a
}
}
foreign class Element{
construct new(a){findIdAndBecomeThat_(a)}
foreign width
foreign height
position=(a){
var b=a.origin
var c=a.size
setPosition_(b.x,b.y,c.width,c.height)
}
visibility=(a){setVisibility_(a)}
zOrder=(a){setZOrder_(a)}
foreign findIdAndBecomeThat_(id)
foreign setPosition_(x,y,w,h)
foreign setVisibility_(v)
foreign setZOrder_(z)
foreign setProp_(nclass,nth,x)
foreign setPropRGBA_(nclass,nth,r,g,b,a)
foreign getProp_(nclass,nth)
foreign getPropRGBA_(nclass,nth,ch)
}
class UIElement{
construct new(a){_e=Element.new(a)}
width{_e.width}
height{_e.height}
position=(a){_e.position=a}
position(a){
_e.position=a
return this
}
visibility=(a){_e.visibility=a}
visibility(a){
_e.visibility=a
return this
}
zOrder=(a){_e.zOrder=a}
zOrder(a){
_e.zOrder=a
return this
}
e{_e}
}
class Point{
construct new(a,b){
_x=a
_y=b
}
x{_x}
y{_y}
x(a){_x=a}
y(a){_y=a}
}
class Size{
construct new(a,b){
_width=a
_height=b
}
width{_width}
height{_height}
width(a){_width=a}
height(a){_height=a}
}
class Rectangle{
construct new(a,b,c,d){
_orig=Point.new(a,b)
_size=Size.new(c,d)
}
construct new(a,b){
_orig=a
_size=b
}
size{_size}
origin{_orig}
scaleByFactor(a){
var b=(_orig.x*a).round
var c=(_orig.y*a).round
var d=((_orig.x+_size.width)*a).round
var e=((_orig.y+_size.height)*a).round
return Rectangle.new(b,c,d-b,e-c)
}
}
class RGBA{
construct new(c,d,e,f){
_r=c
_g=d
_b=e
_a=f
}
whiten(c){
return RGBA.new(_r+(255-_r)*c,_g+(255-_g)*c,_b+(255-_b)*c,a)
}
blacken(c){
return RGBA.new(_r*(1-c),_g*(1-c),_b*(1-c),a)
}
withAlpha(c){
return RGBA.new(_r,_g,_b,c)
}
static grey(c){
return RGBA.new(c,c,c,255)
}
static grey(c,d){
return RGBA.new(c,c,c,d)
}
r{_r}
g{_g}
b{_b}
a{_a}
r=(c){_r=c}
g=(c){_g=c}
b=(c){_b=c}
a=(c){_a=c}
}