﻿package {
	import flash.display.*;
	import flash.events.*;
	import flash.net.*;
	import flash.ui.*;
	import flash.utils.*;
	
	public class Manila extends Sprite {

		//cmp的api接口
		private var api:Object;
		//延时id
		private var timeid:uint;
		//修正加载皮肤时找不到bitmapData属性报错的情况
		public var bitmapData:BitmapData;

		public function Manila() {
			//侦听api的发送
			root.loaderInfo.sharedEvents.addEventListener('api', apiHandler);
		}

		private function apiHandler(e):void {
			//取得cmp的api对象和侦听key，包含2个属性{api,key}
			var apikey:Object = e.data;
			//如果没有取到则直接返回
			if (! apikey) {
				return;
			}
			api = apikey.api;
			//添加侦听事件，必须传入通信key
			//改变大小时调用
			api.addEventListener(apikey.key, 'resize', resizeHandler);
			//状态改变时调用
			api.addEventListener(apikey.key, 'model_state', stateHandler);
			//初始化====================================================================
			//api.tools.output("vplayer");
			//自动关闭右键中窗口项
			var menus:Array = api.cmp.contextMenu.customItems;
			if (menus.length > 1) {
				var newMenu:ContextMenu = new ContextMenu();
				newMenu.hideBuiltInItems();
				newMenu.customItems = [menus[0]];
				api.cmp.contextMenu = newMenu;
			}
			var bg_url:String = api.skin_xml.console.@bg;
			
			//api.tools.output(bg_url);
			api.tools.zip.gZ(bg_url, bgComplete, bgError);
			
			//初始位置尺寸
			resizeHandler();
			//初始化播放状态
			stateHandler();
		}
		
		private function bgError(e:Event):void {
			//api.tools.output(e);
		}
		private function bgComplete(e:Event):void {
			bg_back.addChild(e.target.content);
			resizeHandler();
		}
		
		//尺寸改变时调用
		private function resizeHandler(e:Event = null):void {
			//获取cmp的宽高
			var cw:Number = api.config.width;
			var ch:Number = api.config.height;
			//还原缩放，因为cmp会把背景大小改变，这样要还原，以免比例失调
			//并且设置背景框和cmp一样大小
			this.scaleX = this.scaleY = 1;
			bg_head.width = cw;
			//
			bg_main.y = ch - bg_main.height;
			bg_main.width = cw;
			//
			bg_video.width = cw;
			bg_video.height = ch - 120;
			//
			bg_back.width = cw;
			bg_back.height = ch;
		}

		//播放状态改变时调用
		private function stateHandler(e:Event = null):void {
			var playing:Boolean = false;
			switch (api.config.state) {
				case "connecting":
				case "buffering":
				case "playing":
				case "paused":
					playing = true;
					break;
				default :
				
			}
			api.win_list.list.display = !playing;
			api.win_list.media.display = playing;
			if (playing && api.item.type == "video") {
				bg_video.visible = true;
			} else {
				bg_video.visible = false;
			}
		}
	}

}