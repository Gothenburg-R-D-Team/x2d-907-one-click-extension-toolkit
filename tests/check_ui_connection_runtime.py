from pathlib import Path
import os,sys,json,shutil,hashlib,faulthandler
faulthandler.dump_traceback_later(25,exit=True)
root=Path(__file__).resolve().parents[1];p=root/'src/x2d2_ui_handoff_062/camera'
outer=Path(os.environ['X2D_FIRMWARE_ANALYSIS'])
sys.path.insert(0,os.environ.get('X2D_QT_PYTHONPATH',str(outer/'host-qt-test')))
os.environ.update(QT_QPA_PLATFORM='offscreen',QSG_RHI_BACKEND='software',QML_DISABLE_DISK_CACHE='1')
from PySide6.QtCore import QUrl,QMetaObject,Q_ARG,Q_RETURN_ARG,Qt,QPoint,QObject,QSize,qInstallMessageHandler
from PySide6.QtGui import QGuiApplication,QImage,QPainter,QFontDatabase
from PySide6.QtQml import QQmlEngine,QQmlComponent
from PySide6.QtQuick import QQuickWindow,QQuickImageProvider
from PySide6.QtSvg import QSvgRenderer
from PySide6.QtTest import QTest
work=root/'outputs/ui-connection-qt';work.mkdir(parents=True,exist_ok=True)
preview=work/'previews';preview.mkdir(exist_ok=True)
stock=outer/'x2d-4.2.0/qt-resources/app/qml';icons=outer/'x2d-4.2.0/qt-resources/icons'
module=work/'imports/com/hasselblad/constants';module.mkdir(parents=True,exist_ok=True)
(module/'qmldir').write_text('module com.hasselblad.constants\nsingleton Constants 1.0 Constants.qml\n',encoding='utf-8')
(module/'Constants.qml').write_text('''pragma Singleton
import QtQuick
QtObject {property real scaleFactor:.75;property real scaleFactorX:.75;property real scaleFactorY:.75
property color colorWhite:"white";property color highlightColor:"#dc500b";property string menuItemFontName:"Microsoft YaHei"}
''',encoding='utf-8')
for name in ('buttons/FramedImage.qml','buttons/FramedItem.qml','ScaledImage.qml'):
 target=work/'stock/components'/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(stock/'components'/name,target)
 # Verify the actual first-generation frame, press/key and text code is intact.
 assert target.read_bytes()==(stock/'components'/name).read_bytes()
(work/'stock/components/UiImage.qml').write_text('import QtQuick\nImage { objectName:"DesktopShaderSubstitute" }\n',encoding='utf-8')
# Host Python image providers must render synchronously to avoid a GIL/render
# thread deadlock. Only the desktop image adapter changes; stock button files
# and the production connection controller stay byte-identical.
f=work/'stock/components/ScaledImage.qml';f.write_text(f.read_text(encoding='utf-8').replace('asynchronous: true','asynchronous: false'),encoding='utf-8')
shutil.copy2(p/'X2dNativeMenuModel.qml',work/'X2dNativeMenuModel.qml')
names=['exposureMenu','focusMenu','qualityMenu','cropModesMenu','flashMenu','displayMenu','powerMenu','storageMenu','ibisMenu','wifiMenu','generalMenu']
labels=['曝光','对焦','画质','裁切模式','闪光灯','显示','电源','存储','防抖','Wi-Fi','通用']
entries=[dict(menuName=n,label=label,labelContext='MainMenu',iconSrc='qrc:/icons/'+n,itemEnabled=True) for n,label in zip(names,labels)]
harness=work/'Harness.qml';harness.write_text('''import QtQuick
import "stock/components/buttons" as Stock
Item {
 id:r;width:960;height:720
 property bool master:true;property bool menuEnabled:false;property bool ready:true;property bool installed:true
 property var controller:null;property string lastRoute:"";property int clickCount:0
 ListModel {id:source;function itemEnabled(ix){return get(ix).itemEnabled}}
 X2dNativeMenuModel {id:adapter;sourceModel:source;stockDelegate:tile;playIcon:"file:///system/etc/X2dPlayIcon"}
 GridView {id:grid;objectName:"DemoGrid";x:40;y:24;width:880;height:680;cellWidth:220;cellHeight:214;model:adapter;interactive:false;cacheBuffer:1000}
 Component {id:tile
  Item {objectName:"Tile-"+model.menuName;width:grid.cellWidth;height:grid.cellHeight
   Stock.FramedImage {anchors.horizontalCenter:parent.horizontalCenter;anchors.top:parent.top;anchors.topMargin:12
    width:parent.width;highlightWidth:105;highlightHeight:105;textTopMargin:8;textPixelSize:27
    text:model.label;textColor:"white";source:"image://svg/"+model.iconSrc
    selectable:model.itemEnabled;touchEnabled:selectable;showBoldTextWhenPressed:true
    onClicked:{if(selectable){r.lastRoute=model.menuName;r.clickCount++}}
   }
  }
 }
 function mount(url){
  var component=Qt.createComponent(url)
  if(component.status!==Component.Ready)throw new Error(component.errorString())
  controller=component.createObject(r,{grid:grid,menuModel:adapter,active:Qt.binding(function(){return r.master&&r.menuEnabled&&r.ready&&r.installed})})
  if(!controller)throw new Error(component.errorString())
 }
 function drop(){if(controller){controller.active=false;controller.destroy();controller=null}}
 function renameWifi(label){for(var i=0;i<source.count;i++)if(source.get(i).menuName==="wifiMenu")source.setProperty(i,"label",label)}
 function moveWifi(){for(var i=0;i<source.count;i++)if(source.get(i).menuName==="wifiMenu"){source.move(i,1,1);break}}
 function dropIbis(){for(var i=0;i<source.count;i++)if(source.get(i).menuName==="ibisMenu"){source.remove(i,1);break}}
 function setKnown(value){adapter.supportedLayout=value}
 function stockSnapshot(){var result=[];for(var i=0;i<source.count;i++)result.push(source.get(i));return JSON.stringify(result)}
 Component.onCompleted:{var data='''+json.dumps(entries,ensure_ascii=False)+''';for(var i=0;i<data.length;i++)source.append(data[i])}
}
''',encoding='utf-8')
class Provider(QQuickImageProvider):
 def __init__(self):super().__init__(QQuickImageProvider.Image)
 def requestImage(self,id,size,requested):
  if id.startswith('qrc:/icons/'):file=icons/(id.rsplit('/',1)[-1]+'.svg')
  elif id.startswith('file:///system/etc/'):
   target=id[len('file://'):]+'.svg'
   entry=next(e for e in json.loads((p.parent/'asset-index.json').read_bytes())['assets'] if e['target']==target)
   file=p/entry['source']
  else:raise AssertionError(id)
  assert file.exists(),file
  renderer=QSvgRenderer(str(file));dim=requested if requested.isValid() else QSize(120,120)
  image=QImage(dim,QImage.Format_ARGB32_Premultiplied);image.fill(Qt.transparent)
  painter=QPainter(image);renderer.render(painter);painter.end();size.setWidth(dim.width());size.setHeight(dim.height());return image
messages=[];qInstallMessageHandler(lambda kind,ctx,msg:messages.append(msg))
app=QGuiApplication([]);engine=QQmlEngine();engine.addImportPath(str(work/'imports'));provider=Provider();engine.addImageProvider('svg',provider)
for f in (outer/'x2d-4.2.0/system-root/lib64/qt/lib/fonts').glob('*.ttf'):QFontDatabase.addApplicationFont(str(f))
window=QQuickWindow();window.setColor(Qt.black);window.setGeometry(0,0,960,720);window.show()
component=QQmlComponent(engine,QUrl.fromLocalFile(str(harness)));obj=component.create();assert obj,component.errorString()
obj.setParentItem(window.contentItem())
def call(name,*args):
 assert QMetaObject.invokeMethod(obj,name,Qt.DirectConnection,*[Q_ARG('QVariant',a) for a in args]);app.processEvents()
def visualFind(item,name):
 if item.objectName()==name:return item
 for child in item.childItems():
  found=visualFind(child,name)
  if found:return found
 return None
def frame():
 tile=visualFind(obj,'Tile-wifiMenu');assert tile;button=visualFind(tile,'FramedItem_root');assert button;return button
def snapshot():return QMetaObject.invokeMethod(obj,'stockSnapshot',Qt.DirectConnection,Q_RETURN_ARG('QVariant'))
def source():return frame().property('source').toString()
QTest.qWait(450);assert obj.findChild(QObject,'DemoGrid').property('count')==12
original=source();assert 'wifiMenu' in original
reports=[]
for lang,label in [('zh','连接'),('en','Connections'),('zh-Hant','連線')]:
 filename='X2dConnectionMenu'+('' if lang=='zh' else '.'+lang)+'.qml'
 obj.setProperty('menuEnabled',False);call('mount',QUrl.fromLocalFile(str(p/filename)));QTest.qWait(80)
 before=snapshot();assert frame().property('text')=='Wi-Fi' and source()==original
 if lang=='zh':window.grabWindow().save(str(preview/'连接菜单-关闭.png'))
 obj.setProperty('menuEnabled',True);QTest.qWait(200)
 assert frame().property('text')==label and 'X2dConnectionMenuIcon' in source()
 assert snapshot()==before,'Stock favorite model must not be rewritten'
 if lang=='zh':window.grabWindow().save(str(preview/'连接菜单-开启.png'))
 button=frame();position=button.mapToScene(button.boundingRect().center());QTest.mouseClick(window,Qt.LeftButton,Qt.NoModifier,QPoint(round(position.x()),round(position.y())));QTest.qWait(30)
 assert obj.property('lastRoute')=='wifiMenu' and obj.property('clickCount')>0
 obj.setProperty('master',False);QTest.qWait(30);assert frame().property('text')=='Wi-Fi' and source()==original
 obj.setProperty('master',True);QTest.qWait(30);assert frame().property('text')==label
 obj.setProperty('menuEnabled',False);QTest.qWait(30);assert frame().property('text')=='Wi-Fi' and source()==original
 obj.setProperty('menuEnabled',True);QTest.qWait(30);call('drop');QTest.qWait(30)
 assert frame().property('text')=='Wi-Fi' and source()==original
 call('renameWifi','Stock refreshed');QTest.qWait(30);assert frame().property('text')=='Stock refreshed'
 call('renameWifi','Wi-Fi');reports.append(dict(language=lang,label=label,stockActionUnchanged=True,stockModelUnchanged=True,offAndDestructionRestoreLiveBindings=True))
call('mount',QUrl.fromLocalFile(str(p/'X2dConnectionMenu.qml')));obj.setProperty('menuEnabled',True);QTest.qWait(40)
call('renameWifi','Updated while decorated');QTest.qWait(30);assert frame().property('text')=='连接'
obj.setProperty('menuEnabled',False);QTest.qWait(30);assert frame().property('text')=='Updated while decorated'
call('renameWifi','Wi-Fi');obj.setProperty('menuEnabled',True);call('moveWifi');QTest.qWait(350);assert frame().property('text')=='连接'
call('setKnown',False);QTest.qWait(100);assert frame().property('text')=='Wi-Fi' and source()==original
call('setKnown',True);QTest.qWait(350);assert frame().property('text')=='连接'
obj.setProperty('ready',False);QTest.qWait(30);assert frame().property('text')=='Wi-Fi'
obj.setProperty('ready',True);call('dropIbis');QTest.qWait(350)
assert obj.findChild(QObject,'DemoGrid').property('count')==11 and frame().property('text')=='连接'
bad=[m for m in messages if any(k in m for k in ('ReferenceError','TypeError','Cannot assign','Unable to assign','Binding loop','Error decoding','not a type','Failed to'))]
assert not bad,bad
call('drop');obj.deleteLater();app.processEvents()
report=dict(languages=reports,stockFramedImageAndPressHandlersUnmodified=True,sourceLabelsRefreshAfterDisable=True,
 rowReorderingHandled=True,cfvTenOriginalItemsLayoutHandled=True,unsupportedLayoutRestoresStock=True,unreadyRestoresStock=True,shadersAndConstantsSimulated=True,
 productionConnectionControllerExecuted=True,cameraAccess=False,qmlErrors=bad,hardwareAppearanceVerified=False)
(work/'validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print(json.dumps(report,ensure_ascii=False))
