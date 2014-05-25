﻿package {
	import flash.display.*;
	import flash.events.*;
	import flash.filters.*;
	import flash.geom.*;
	import flash.media.*;
	import flash.net.*;
	import flash.ui.*;
	import flash.utils.*;

	public final class CjvmModel extends Object {
		public var position:Number = 0;
		public var loaded:Boolean;
		//下载字节和总字节
		public var bl:int;
		public var bt:int;
		//时间控制者
		public var timer:Sprite = new Sprite();
		public var transform:SoundTransform;
		public var nc:NetConnection;
		public var ns:NetStream;
		public var vv:Video;
		public var isBuffering:Boolean = false;
		public var isFlush:Boolean = false;
		public var streaming:Boolean = false;
		public var keyframes:Object;
		public var meta:Boolean;
		public var mp4:Boolean;
		
		//====================================================================================
		public var CMP:Object;
		public var apikey:Object;
		public var api:Object;

		//原始数据
		public var xml:XMLList;
		//文件列表
		public var list:Array = [];
		//当前文件信息
		public var file:Object = {};
		//第几段，默认从0开始
		public var index:int = 0;
		public function CjvmModel(_apikey:Object):void {
			apikey = _apikey;
			api = apikey.api;
			//取得cmp构造函数
			CMP = api.cmp.constructor;
			//模块初始定义
			transform = new SoundTransform();
			nc = new NetConnection();
			nc.addEventListener(NetStatusEvent.NET_STATUS, statusHandler);
			nc.addEventListener(SecurityErrorEvent.SECURITY_ERROR, errorHandler);
			nc.addEventListener(IOErrorEvent.IO_ERROR, errorHandler);
			nc.addEventListener(AsyncErrorEvent.ASYNC_ERROR, errorHandler);
			nc.client = new NetClient(this);
			CMP.addEventListener("video_effect", effectHandler);
			CMP.addEventListener("video_smoothing", smoothingHandler);
			
			//CJVM events callback
			CMP.addEventListener("cjvm_error", onError);
			CMP.addEventListener("cjvm_complete", onComplete);
			
		}
		
		
		//加载地址配置
		public function loadData():void {
			api.sendState("connecting");
			index = 0;
			//加载文件信息
			
			//转到调用js完成列表拼装
			CMP.ei.eic("cjvm_load", api.item.src);
			
		}
		public function onError(e:Event = null):void {
			api.sendEvent("model_error", "加载视频配置失败");
		}
		
		//信息加载完成
		public function onComplete(e:Object):void {
			var str:String = e.data + "";
			
			//api.tools.output(str);
			
			//解析数据
			xml = api.tools.strings.XL(str);
			//总共多少分段
			var len:int = xml.children().length();
			if (!len) {
				onError();
				return;
			}
			
			//读取所有属性
			var atts:XMLList = xml.attributes();
			for each (var att:XML in atts){ 
				var val:String = att.toString();
				if (val) {
					var nam:String = att.localName();
					if (!api.item[nam]) {
						api.item[nam] = api.tools.strings.parse(api.tools.strings.backslash(val));
					}
				}
			}
			
			//读取所有列表
			list = [];
			var duration:Number = 0;
			var bytes:Number = 0;
			var children:XMLList = xml.children();
			var i:int = 0;
			for each (var child:XML in children) {
				var item:Object = {};
				item.index = i;
				//duration
				item.duration = parseFloat(child.@duration);
				item.duration_start = duration;
				duration += item.duration;
				item.duration_end = duration;
				//bytes
				item.bytes = parseFloat(child.@bytes);
				item.start_bytes = bytes;
				bytes += item.bytes;
				item.end_bytes = bytes;
				//src
				item.src = child.@src;
				//
				list.push(item);
			}
			
			//如果没有定义总的就保存到总的
			if (!api.item.duration) {
				api.item.duration = duration;
			}
			if (!api.item.bytes) {
				api.item.bytes = bytes;
			}
			
			//开始加载
			nc.connect(null);
			
		}
		
		//=============================================================================================================
		
		public function load():void {
			api.sendState("connecting");
			loaded = false;
			
			loadData();
		}
		
		public function connect():void {
			ns = new NetStream(nc);
			ns.bufferTime = api.config.buffer_time;
			ns.client = new NetClient(this);
			ns.addEventListener(AsyncErrorEvent.ASYNC_ERROR, errorHandler);
			ns.addEventListener(IOErrorEvent.IO_ERROR, errorHandler);
			ns.addEventListener(NetStatusEvent.NET_STATUS, statusHandler);
			vv = new Video();
			vv.attachNetStream(ns);
			//
			file = list[index];
			if (file) {
				var url:String = file.src;
				url = url.replace("{start_seconds}", 0);
				url = url.replace("{start_bytes}", 0);
				api.item.url = url;
				ns.play(url);
				interval("add", [progressHandler]);
			}
		}
		
		public function play():void {
			//如果是rtmp不能在第一次播放时使用resume
			ns.resume();
			volume();
			interval("add", [timeHandler]);
		}
		public function pause():void {
			interval("del", [timeHandler]);
			ns.pause();
			api.sendState("paused");
		}
		public function stop():void {
			interval("del", [timeHandler, progressHandler, sizeHandler]);
			//清除流媒体位置
			api.item.start_seconds = 0;
			api.item.start_bytes = 0;
			streaming = false;
			keyframes = undefined;
			meta = false;
			//初始化到第一个
			index = 0;
			
			//需要开启一个新的video，清除之前的宽高，以及平滑层
			if (vv) {
				vv.clear();
				vv.visible = false;
				vv = null;
			}
			if (ns) {
				//关闭流
				ns.removeEventListener(AsyncErrorEvent.ASYNC_ERROR, errorHandler);
				ns.removeEventListener(IOErrorEvent.IO_ERROR, errorHandler);
				ns.removeEventListener(NetStatusEvent.NET_STATUS, statusHandler);
				//必须关闭，不能暂停，否则mp3的频谱不显示
				try {
					ns.close();
				} catch (e:Error) {
				}
				ns = null;
			}
			if (nc.connected) {
				nc.close();
			}
		}
		
		public function volume():void {
			transform.volume = api.config.volume;
			transform.pan = api.config.panning;
			ns.soundTransform = transform;
		}
		public function seek(val:Number):void {
			var pos:Number;
			
			//api.tools.output(val);	
			
			if (val < 0 || val > 1) {
				pos = file.duration_start + ns.time + val;
			} else {
				pos = api.item.duration * val;
			}
			
			api.tools.output(pos);	
			
			if (pos == 0) {
				index = 0;
			} else {
				for (var i:int = 0, len:int = list.length; i < len; i ++) {
					var item:Object = list[i];
					if (pos >= item.duration_start && pos <= item.duration_end) {
						index = i;
						break;
					}
				}
			}
			
			//当前文件
			file = list[index];
			
			if (!file) {
				return;
			}
			
			//当前段的位置
			var currentPos:Number = pos - file.duration_start;
			
			if (api.item.starttype) {
				currentPos = pos;
			}
			
			var ss:Number = 0;
			var sb:Number = 0;
			if(keyframes) {
				for (var k:int = 0, kl:int = keyframes.times.length - 1; k < kl; k ++) {
					if(keyframes.times[k] <= currentPos && keyframes.times[k + 1] >= currentPos) {
						break;
					}
				}
				ss = keyframes.times[k];
				sb = keyframes.filepositions[k];
			}
			
			//trace(pos, ss)
			
			//流媒体跳进
			//trace("start_seconds:" + ss, api.item.start_seconds, "start_bytes:" + sb, api.item.start_bytes);
			//如果在没下载的范围，否则直接在已下载缓存搜索
			if(sb < api.item.start_bytes || sb >= api.item.start_bytes + ns.bytesLoaded) {
				//状态变为连接中
				api.sendState("connecting");
				loaded = false;
				//先清理时间等事件
				interval("del", [timeHandler, progressHandler, sizeHandler]);
				
				//新的位置
				api.item.start_seconds = ss;
				api.item.start_bytes = sb;
				api.item.position = pos;
				
				var url:String = file.src;
				url = url.replace("{start_seconds}", ss);
				url = url.replace("{start_bytes}", sb);
				api.item.url = url;
				//标记开始使用steam了
				streaming = true;
				
				//api.tools.output(url);
				
				//播放新地址和新下载，不用新建，也就是不能用全局play()方法
				ns.play(url);
				interval("add", [progressHandler]);
				//重新连接，直接返回
				return;
			}
			//普通逐渐式下载跳进
			if(keyframes) {
				ns.seek(ss);
			} else {
				ns.seek(currentPos);
			}
			//如果暂停则恢复播放
			if (api.config.state == "paused") {
				play();
			}
		}
		//=========================================================================================
		public function statusHandler(e:NetStatusEvent):void {
			var s:String = e.info.code;
			//trace(s+" | "+e.info.level + " | " + url);
			switch (s) {
				case "NetConnection.Connect.Success":
					//已经连接Net，开始连接流媒体
					connect();
					break;
				case "NetStream.Play.Start" :
					//播放已开始
					start();
					break;
				case "NetStream.Buffer.Empty" :
					//数据的接收速度不足以填充缓冲区
					if (!isFlush) {
						isBuffering = true;
					}
					break;
				case "NetStream.Buffer.Full" :
					//缓冲区已满并且流将开始播放
					isBuffering = false;
					break;
				case "NetStream.Buffer.Flush" :
					//数据已完成流式处理，剩余的缓冲区将被清空，修正无总时间视频长度,和纵横比
					isFlush = true;
					isBuffering = false;
					break;
				case "NetStream.Seek.InvalidTime" :
					//对于使用渐进式下载方式下载的视频，用户已尝试跳过到目前为止已下载的视频数据的结尾或在整个文件已下载后跳过视频的结尾进行搜寻或播放
					isBuffering = true;
					break;
				case "NetStream.Seek.Notify" :
					//搜寻操作完成
					isBuffering = false;
					break;
				case "NetStream.Play.Stop" :
					//播放已结束
					completeHandler();
					break;
				case "NetConnection.Connect.Rejected" :
				case "NetConnection.Connect.Failed" :
				case "NetStream.Play.StreamNotFound" :
				case "NetStream.Play.Failed" :
				case "NetStream.Failed" :
				case "NetStream.Play.FileStructureInvalid" :
				case "NetStream.Play.NoSupportedTrackFound" :
					//视频流错误
					nsError(s);
					break;
				default :
			}
		}
		//播放流开始
		public function start():void {
			//状态
			isBuffering = true;
			isFlush = false;
			api.item.data = true;
			//非straming重连需要发送开始事件
			if (!streaming) {
				api.sendEvent("model_start");
				api.showMixer(false);
			}
			//无需在第一次播放时使用resume，尤其是rtmp类型
			volume();
			//获取时间和宽高
			interval("add", [timeHandler, sizeHandler]);
		}
		//大小控制
		public function sizeHandler(e:Event):void {
			if (!api.item || !vv) {
				return;
			}
			
			var iw:Number = parseInt(api.item.width);
			var ih:Number = parseInt(api.item.height);
			if (iw && ih) {
				size(iw, ih);
			} else if (vv.videoWidth && vv.videoHeight) {
				size(vv.videoWidth, vv.videoHeight);
			} else {
				if (api.item.src) {
					//停止仅有声音的视频对宽高的计算
					var arr:Array = api.item.src.split(".");
					var ext:String = arr[arr.length - 1].toLowerCase();
					if (ext == "m4a" || ext == "aac" || api.tools.types.EXTS[ext] == api.tools.types.SOUND) {
						interval("del", [sizeHandler]);
						//尝试启用频谱
						api.showMixer(true);
					}
				}
			}
		}
		//设置尺寸
		public function size(vw:Number, vh:Number):void {
			interval("del", [sizeHandler]);
			vv.width = vw;
			vv.height = vh;
			api.showMedia(vv);
			//初始化效果处理
			effectHandler();
			smoothingHandler();
		}
		//时间控制
		public function timeHandler(e:Event):void {
			//当前段的时间修正
			position = ns.time + file.duration_start;
			
			//发送时间变更事件
			if (position != api.item.position && api.config.state == "playing") {
				api.item.position = position;
				api.sendEvent("model_time");
			}
			//检测缓冲状态
			if (isBuffering && !loaded) {
				var bper:Number = Math.floor(ns.bufferLength * 100 / api.config.buffer_time);
				//trace(bper);
				if (bper < 100) {
					api.config.buffer_percent = bper;
					api.sendState("buffering");
				}
			} else if(api.config.state != "playing") {
				api.sendState("playing");
			}
			
		}
		//下载管理
		public function progressHandler(e:Event):void {
			//不能用e，Enterframe的e有用 
			//trace(ns.bytesLoaded, ns.bytesTotal);
			//下载状态
			if(ns.bytesTotal > 0 && ns.bytesLoaded < ns.bytesTotal) {
				var ld:int = ns.bytesLoaded;
				if (!streaming) {
					bt = ns.bytesTotal;
				} else if (ns.bytesTotal < bt) {
					ld += bt - ns.bytesTotal;
				}
				if (bl == ld) {
					return;
				}
				bl = ld;
				var pre:Number = 0;
				if (bt > 0) {
					pre = bl / bt;
				}
				
				//先算当前段在整个中的百分比
				var per1:Number = file.duration_start / api.item.duration;
				//当前百分比
				var per2:Number = file.duration / api.item.duration * pre;
				//修正下载百分比
				var per:Number = per1 + per2;
				
				api.sendEvent("model_loading", per);
			} else {
				interval("del", [progressHandler]);
				if (index == list.length - 1) {
					api.sendEvent("model_loaded");
				}
				loaded = true;
			}
		}
		//是否平滑处理
		public function smoothingHandler(e:Object = null):void {
			if (!vv) {
				return;
			}
			if (e) {
				//有数据才改值，否则有事件才反转值
				if (e.data != null) {
					api.config.video_smoothing = api.tools.strings.tof(e.data.toString());
				} else {
					api.config.video_smoothing = !api.config.video_smoothing;
				}
			}
			vv.smoothing = api.config.video_smoothing;
		}
		//视频效果
		public function effectHandler(e:Object = null):void {
			if (!vv) {
				return;
			}
			//黑白高亮效果
			var cmf:BitmapFilter;
			if (e && e.data != null) {
				var arr:Array = api.tools.strings.array(e.data.toString());
				cmf = new ColorMatrixFilter(arr);
			} else if (api.config.video_blackwhite && api.config.video_highlight) {
				cmf = new ColorMatrixFilter([1.5, 0, 0, 0, 0, 1.5, 0, 0, 0, 0, 1.5, 0, 0, 0, 0, 0, 0, 0, 1, 0]);
			} else if (api.config.video_blackwhite) {
				cmf = new ColorMatrixFilter([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0]);
			} else if (api.config.video_highlight) {
				cmf = new ColorMatrixFilter([1.5, 0, 0, 0, 0, 0, 1.5, 0, 0, 0, 0, 0, 1.5, 0, 0, 0, 0, 0, 1, 0]);
			}
			if (cmf) {
				vv.filters = [cmf];
			} else {
				vv.filters = null;
			}
		}
		public function errorHandler(e:Event):void {
			nsError(e);
		}
		//视频流错误
		public function nsError(dat:Object):void {
			api.sendEvent("model_error", dat);
		}
		//段播放完成
		public function completeHandler():void {
			if (index < list.length - 1) {
				//播放下一段
				index ++;
				file = list[index];
				if (file) {
					
					//状态变为连接中
					api.sendState("connecting");
					loaded = false;
					//先清理时间等事件
					interval("del", [timeHandler, progressHandler, sizeHandler]);
				
					var url:String = file.src;
					url = url.replace("{start_seconds}", 0);
					url = url.replace("{start_bytes}", 0);
					api.item.url = url;
					//标记开始使用steam了
					streaming = true;
					//播放新地址和新下载，不用新建，也就是不能用全局play()方法
					ns.play(url);
					interval("add", [progressHandler]);
					
					//返回
					return;
				} 
			}
			
			//整体完成
			finish();
		}
		
		//整体完成
		public function finish():void {
			//先停止当前模块
			stop();
			api.sendState("completed");
		}
		//取得媒体资料
		public function metaHandler(info:Object):void {
			api.item.data = true;
			
			//trace(info.type);
			//for (var i:String in info) {
			//trace(i + ": " + info[i]);
			//}
			//重新修正宽高比
			if (info.width && info.height) {
				size(info.width, info.height);
			}
			if(info['type'] == 'metadata' && !meta) {
				meta = true;
				if(info.seekpoints) {
					mp4 = true;
					keyframes = skf(info.seekpoints);
				} else if(info.keyframes) {
					mp4 = false;
					keyframes = info.keyframes;
				}
			}
			api.sendEvent("model_meta", info);
		}
		
		public function skf(dat:Object):Object {
			var kfr:Object = new Object();
			kfr.times = new Array();
			kfr.filepositions = new Array();
			for (var i:String in dat) {
				kfr.times[i] = Number(dat[i]['time']);
				kfr.filepositions[i] = Number(dat[i]['offset']);
			}
			return kfr;
		}
		
		//批量处理侦听==================================================================
		
		public function interval(type:String, arr:Array):void {
			var f:Function;
			for (var i:int = 0; i < arr.length; i ++) {
				f = arr[i];
				if (f is Function) {
					timer.removeEventListener(Event.ENTER_FRAME, f);
					if (type == "add") {
						timer.addEventListener(Event.ENTER_FRAME, f);
					}
				}
			}
		}
		
		//===================================================================================================================
		
		public function random(input:Number):Number {
			return Math.round(input * Math.random());
		}

	}
}