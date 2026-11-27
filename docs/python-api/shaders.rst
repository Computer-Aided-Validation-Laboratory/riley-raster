Shaders and shader pipes
========================

Assign shader sources or pipes to camera roles through :class:`riley.MeshShaderSet`.
For :class:`riley.SpeckleShader` and its pattern parameters, see :doc:`../procedural`.

Shader sources
--------------

.. autoclass:: riley.TextureShader

.. autoclass:: riley.TextureSample
   :members:
   :undoc-members:

.. autoclass:: riley.TextureSampleMode
   :members:
   :undoc-members:

.. autoclass:: riley.NodalShader

.. autoclass:: riley.ScaleOver
   :members:
   :undoc-members:

.. autoclass:: riley.FunctionShader

.. autoclass:: riley.FuncShaderBuiltin
   :members:
   :undoc-members:

.. autoclass:: riley.FuncShaderParams

.. autoclass:: riley.FuncCoordMode
   :members:
   :undoc-members:

.. autoclass:: riley.FunctionMultiShader

.. autoclass:: riley.FunctionChannel

.. py:data:: riley.RileyShader

   Union of :class:`riley.TextureShader`, :class:`riley.NodalShader`,
   :class:`riley.FunctionShader`, :class:`riley.FunctionMultiShader`, and
   :class:`riley.SpeckleShader`.

.. py:data:: riley.Shader

   Alias for :data:`riley.RileyShader`.

Pipes and registers
-------------------

.. autoclass:: riley.ShaderPipe

.. autoclass:: riley.Register

.. autoclass:: riley.RegisterKind
   :members:
   :undoc-members:

Pipe stages
-----------

.. autoclass:: riley.ShaderSource

.. autoclass:: riley.GreyToEmissivity

.. autoclass:: riley.ClampStage

.. autoclass:: riley.AffineMap

.. autoclass:: riley.LUTMap

.. autoclass:: riley.Blend

.. autoclass:: riley.Normalise

Resolvers
---------

.. autoclass:: riley.ShaderResolver

.. autoclass:: riley.ResolverKind
   :members:
   :undoc-members:

.. autoclass:: riley.ResolverOp

.. autoclass:: riley.ResolverOpKind
   :members:
   :undoc-members:
