package laya.d3.core.render {
	import laya.d3.component.Component3D;
	import laya.d3.core.Sprite3D;
	import laya.d3.core.fileModel.Mesh;
	import laya.d3.core.fileModel.SubMesh;
	import laya.d3.core.material.Material;
	import laya.d3.graphics.IndexBuffer3D;
	import laya.d3.graphics.StaticBatch;
	import laya.d3.graphics.StaticBatchManager;
	import laya.d3.graphics.VertexBuffer3D;
	import laya.d3.graphics.VertexDeclaration;
	import laya.d3.math.Vector3;
	import laya.d3.resource.tempelet.SubMeshTemplet;
	import laya.utils.Stat;
	import laya.webgl.WebGLContext;
	
	/**
	 * <code>RenderQuene</code> 类用于实现渲染队列。
	 */
	public class RenderQuene {
		/** 定义只读渲染队列标记。*/
		public static const NONEWRITEDEPTH:int = 0;
		/** 定义非透明渲染队列标记。*/
		public static const OPAQUE:int = 1;
		/** 定义非透明、双面渲染队列标记。*/
		public static const OPAQUE_DOUBLEFACE:int = 2;
		
		/** 透明混合渲染队列标记。*/
		public static const ALPHA_BLEND:int = 3;
		/** 透明混合、双面渲染队列标记。*/
		public static const ALPHA_BLEND_DOUBLEFACE:int = 4;
		/** 透明加色混合。*/
		public static const ALPHA_ADDTIVE_BLEND:int = 5;
		/** 透明加色混合、双面渲染队列标记。*/
		public static const ALPHA_ADDTIVE_BLEND_DOUBLEFACE:int = 6;
		
		/** 定义深度只读、透明混合渲染队列标记。*/
		public static const DEPTHREAD_ALPHA_BLEND:int = 7;
		/** 定义深度只读、透明混合、双面渲染队列标记。*/
		public static const DEPTHREAD_ALPHA_BLEND_DOUBLEFACE:int = 8;
		/** 定义深度只读、透明加色混合。*/
		public static const DEPTHREAD_ALPHA_ADDTIVE_BLEND:int = 9;
		/** 定义深度只读、透明加色混合、双面渲染队列标记。*/
		public static const DEPTHREAD_ALPHA_ADDTIVE_BLEND_DOUBLEFACE:int = 10;
		
		/**
		 *@private
		 */
		private static function _sort(a:RenderObject, b:RenderObject):* {
			if (a.owner.isStatic && b.owner.isStatic) {
				var aDecID:int = a.renderElement.getVertexBuffer().vertexDeclaration.id;
				var bDecID:int = b.renderElement.getVertexBuffer().vertexDeclaration.id;
				var decID:int = aDecID - bDecID;
				if (decID !== 0)
					return decID;
				
				if (a.material && b.material) {
					var byMat:int = a.material.id - b.material.id;
					if (byMat !== 0)
						return byMat;
				}
			}
			return a.sortID - b.sortID;
		}
		
		/** @private */
		private var _renderObjects:Array;
		/** @private */
		private var _length:int;
		/** @private */
		private var _staticRenderObjects:Array;
		/** @private */
		private var _staticLength:int;
		/** @private */
		private var _merageRenderObjects:Array;
		/** @private */
		private var _merageLength:int;
		/** @private */
		private var _renderConfig:RenderConfig;
		/** @private */
		private var _staticBatchManager:StaticBatchManager;
		
		/**
		 * 获取队列长度。
		 * @return 队列长度。
		 */
		public function get length():int {
			return _length;
		}
		
		/**
		 * 创建一个 <code>RenderQuene</code> 实例。
		 * @param renderConfig 渲染配置。
		 */
		public function RenderQuene(renderConfig:RenderConfig) {
			_renderConfig = renderConfig;
			_renderObjects = [];
			_length = 0;
			_staticRenderObjects = [];
			_staticLength = 0;
			_merageRenderObjects = [];
			_merageLength = 0;
			_staticBatchManager = new StaticBatchManager();
		}
		
		/**
		 * @private
		 * 更新组件preRenderUpdate函数
		 * @param	state 渲染相关状态
		 */
		protected function _preRenderUpdateComponents(sprite3D:Sprite3D, state:RenderState):void {
			for (var i:int = 0; i < sprite3D.componentsCount; i++) {
				var component:Component3D = sprite3D.getComponentByIndex(i);
				(!component.started) && (component._start(state), component.started = true);
				(component.isActive) && (component._preRenderUpdate(state));
			}
		}
		
		/**
		 * @private
		 * 更新组件postRenderUpdate函数
		 * @param	state 渲染相关状态
		 */
		protected function _postRenderUpdateComponents(sprite3D:Sprite3D, state:RenderState):void {
			for (var i:int = 0; i < sprite3D.componentsCount; i++) {
				var component:Component3D = sprite3D.getComponentByIndex(i);
				(!component.started) && (component._start(state), component.started = true);
				(component.isActive) && (component._postRenderUpdate(state));
			}
		}
		
		/**
		 * @private
		 * 应用渲染状态到显卡。
		 * @param gl WebGL上下文。
		 */
		public function _setState(gl:WebGLContext):void {
			WebGLContext.setDepthTest(gl, _renderConfig.depthTest);
			WebGLContext.setDepthMask(gl, _renderConfig.depthMask);
			
			WebGLContext.setBlend(gl, _renderConfig.blend);
			WebGLContext.setBlendFunc(gl, _renderConfig.sFactor, _renderConfig.dFactor);
			WebGLContext.setCullFace(gl, _renderConfig.cullFace);
			WebGLContext.setFrontFaceCCW(gl, _renderConfig.frontFace);
		}
		
		/**
		 * @private
		 * 更新渲染队列。
		 * @param	state 渲染状态。
		 */
		public function _render(state:RenderState):void {
			_renderObjects.length = _length;
			_renderObjects.sort(_sort);
			
			var lastIsStatic:Boolean = false;
			var lastMaterial:Material;
			var lastVertexDeclaration:VertexDeclaration;
			var lastCanMerage:Boolean;
			var curStaticBatch:StaticBatch;
			
			var currentRenderObjIndex:int = 0;
			for (var i:int = 0, n:int = _length; i < n; i++) {
				var renderObj:RenderObject = _renderObjects[i];
				var renderElement:IRender = renderObj.renderElement;
				var isStatic:Boolean = renderObj.owner.isStatic;
				//isStatic = false;
				
				var vb:VertexBuffer3D = renderElement.getVertexBuffer(0);
				if ((lastMaterial === renderObj.material) && (lastVertexDeclaration === vb.vertexDeclaration) && lastIsStatic && isStatic && (renderElement.VertexBufferCount === 1) && renderObj.owner.visible) {
					if (!lastCanMerage) {
						curStaticBatch = _staticBatchManager.getStaticBatchQneue(lastVertexDeclaration, lastMaterial);
						
						var lastRenderObj:RenderObject = _renderObjects[i - 1];
						
						if (!curStaticBatch.addRenderObj(lastRenderObj.renderElement) || !curStaticBatch.addRenderObj(renderElement)) {
							lastCanMerage = false;
							lastIsStatic = isStatic;
							lastMaterial = renderObj.material;
							lastVertexDeclaration = vb.vertexDeclaration;
							
							_merageRenderObjects[_merageLength++] = _renderObjects[currentRenderObjIndex++];
							continue;
						}
						
						var batchObject:RenderObject = _getStaticRenderObj();
						batchObject.renderElement = curStaticBatch;
						batchObject.type = 1;
						
						_merageRenderObjects[_merageLength - 1] = batchObject;
						currentRenderObjIndex++;
					} else {
						if (!curStaticBatch.addRenderObj(renderElement)) {
							lastCanMerage = false;
							lastIsStatic = isStatic;
							lastMaterial = renderObj.material;
							lastVertexDeclaration = vb.vertexDeclaration;
							
							_merageRenderObjects[_merageLength++] = _renderObjects[currentRenderObjIndex++];
							continue;
						}
						currentRenderObjIndex++;
					}
					lastCanMerage = true;
				} else {
					_merageRenderObjects[_merageLength++] = _renderObjects[currentRenderObjIndex++];
					lastCanMerage = false;
				}
				lastIsStatic = isStatic;
				lastMaterial = renderObj.material;
				lastVertexDeclaration = vb.vertexDeclaration;
			}
			_staticBatchManager.garbageCollection();
			_staticBatchManager._finsh();
			
			var preShaderValue:int = state.shaderValue.length;
			var renObj:RenderObject;
			for (i = 0, n = _merageLength; i < n; i++) {
				renObj = _merageRenderObjects[i];
				var preShadeDef:int;
				if (renObj.type === 0) {
					var owner:Sprite3D = renObj.owner;
					state.owner = owner;
					state.renderObj = renObj;
					preShadeDef = state.shaderDefs.getValue();
					_preRenderUpdateComponents(owner, state);
					(owner.visible) && (renObj.renderElement._render(state));
					_postRenderUpdateComponents(owner, state);
					state.shaderDefs.setValue(preShadeDef);
				} else if (renObj.type === 1) {
					state.owner = null;
					state.renderObj = renObj;
					preShadeDef = state.shaderDefs.getValue();
					(renObj.renderElement._render(state));
					state.shaderDefs.setValue(preShadeDef);
				}
				
				state.shaderValue.length = preShaderValue;
			}
		}
		
		/**
		 * 获取队列中的渲染物体。
		 * @param gl WebGL上下文。
		 */
		public function get():RenderObject {
			var o:RenderObject = _renderObjects[_length++];
			return o || (_renderObjects[_length - 1] = new RenderObject());
		}
		
		private function _getStaticRenderObj():RenderObject {
			var o:RenderObject = _staticRenderObjects[_staticLength++];
			return o || (_staticRenderObjects[_staticLength - 1] = new RenderObject());
		}
		
		/**
		 * 重置并清空队列。
		 */
		public function reset():void {
			_length = 0;
			_staticLength = 0;
			_merageLength = 0;
		}
	
	}
}