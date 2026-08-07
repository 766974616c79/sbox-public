HEADER
{
	DevShader = true;
	Version = 1;
}

MODES
{
	Default();
	Forward();
}

FEATURES
{
	#include "ui/features.hlsl"
}

COMMON
{
	#include "system.fxc"
	#include "common.fxc"
	#include "vr_common.fxc"
	#include "common/Bindless.hlsl"

	DynamicCombo( D_WORLDPANEL, 0..1, Sys( ALL ) );
	DynamicCombo( D_NO_ZTEST, 0..1, Sys( ALL ) );

	struct BoxInstanceData
	{
		float4 Rect;
		uint Color;
		float4 BorderRadius;
		float4 BorderSize;
		uint BorderColorL;
		uint BorderColorT;
		uint BorderColorR;
		uint BorderColorB;
		int TextureIndex;
		int SamplerIndex;
		int BackgroundRepeat;
		float BackgroundAngle;
		float4 BackgroundRect;
		uint BackgroundTint;
		int BorderImageIndex;
		int BorderImageSamplerIndex;
		int BorderImageMode;
		int BorderImageFill;
		float4 BorderImageSlice;
		uint BorderImageTint;
		int Flags;
		int ScissorIndex;
		int Mode;
		int TransformIndex;
		int InverseScissorIndex;
	};

	float4 UnpackColor( uint packed )
	{
		float4 c;
		c.r = (float)(packed & 0xFF) / 255.0;
		c.g = (float)((packed >> 8) & 0xFF) / 255.0;
		c.b = (float)((packed >> 16) & 0xFF) / 255.0;
		c.a = (float)((packed >> 24) & 0xFF) / 255.0;
		return c;
	}

	struct TransformData
	{
		float4x4 Mat;
	};

	struct ScissorData
	{
		float4 Rect;
		float4 CornerRadius;
		float4x4 TransformMat;
		int Invert;
	};

	// Must match GPUGradientInstance in GPUBoxInstance.cs. Stop colors are straight
	// alpha in sRGB space; Angle is radians - 0 points down the panel for a linear
	// gradient, straight up for a conic one.
	struct GradientData
	{
		float4 StopColors[8];
		float StopOffsets[8];
		int Count;
		float Angle;
		int Type;			// 0 linear, 1 radial, 2 conic
		int SizeMode;		// radial: 0 farthest-side, 1 farthest-corner, 2 closest-side, 3 closest-corner
		float2 Center;		// radial and conic
		int CenterUnits;	// bit 0/1 set when that centre axis is a fraction of the box, not pixels
		int Circle;			// radial: 1 for a circle instead of an ellipse
	};

	StructuredBuffer<BoxInstanceData> BoxInstances < Attribute( "BoxInstances" ); >;
	StructuredBuffer<ScissorData> ScissorBuffer < Attribute( "ScissorBuffer" ); >;
	StructuredBuffer<TransformData> TransformBuffer < Attribute( "TransformBuffer" ); >;
	StructuredBuffer<GradientData> GradientBuffer < Attribute( "GradientBuffer" ); >;

}

struct PixelInput
{
	float4 vColor : COLOR0;
	float4 vTexCoord : TEXCOORD0;
	float4 vPositionPanelSpace : TEXCOORD2;
	nointerpolation uint iInstanceID : TEXCOORD3;
	float4 vPositionPs : SV_Position;
};

struct VS_INPUT
{
	float3 pos : POSITION < Semantic( None ); >;
};

VS
{
	#include "math_general.fxc"
	#include "instancing.fxc"

	#define EPSILON 0.000001

	float4 g_vViewport < Source( Viewport ); >;
	float4x4 g_matTransform < Attribute( "TransformMat" ); >;
	float4x4 LayerMat < Attribute( "LayerMat" ); >;
	float4x4 g_matWorldPanel < Attribute( "WorldMat" ); >;
	int InstanceOffset < Attribute( "InstanceOffset" ); Default( 0 ); >;

	BoolAttribute( ui, true );
	BoolAttribute( ScreenSpaceVertices, true );

	static const float2 QuadPositions[4] =
	{
		float2( 0, 0 ),
		float2( 1, 0 ),
		float2( 1, 1 ),
		float2( 0, 1 ),
	};

	PixelInput MainVs( uint nVertexID : SV_VertexID, uint nInstanceID : SV_InstanceID )
	{
		PixelInput o;

		uint instanceIndex = nInstanceID + InstanceOffset;
		float2 corner = QuadPositions[nVertexID];
		BoxInstanceData inst = BoxInstances[instanceIndex];

		float2 vPositionSs = inst.Rect.xy + corner * inst.Rect.zw;

		float4 vViewport = g_vViewport;
		float4x4 instTransform = TransformBuffer[inst.TransformIndex].Mat;
		float4 vMatrix = mul( LayerMat, mul( instTransform, float4( vPositionSs, 0, 1 ) ) );

		#if !( D_WORLDPANEL )
		{
			vPositionSs = vMatrix.xy / vMatrix.w;

			o.vPositionPs.xy = 2.0 * ( vPositionSs - vViewport.xy ) / vViewport.zw - float2( 1.0, 1.0 );
			o.vPositionPs.y *= -1.0;
			o.vPositionPs.z = 1.0;
			o.vPositionPs.w = 1.0 + EPSILON;
		}
		#else
		{
			float3 vPositionLocal = vMatrix.xyz / vMatrix.w;
			vPositionSs = vPositionLocal.xy;

			o.vPositionPs = float4( vPositionLocal, 1 );
			o.vPositionPs.y *= -1.0;

			float3 vPositionWs = mul( g_matWorldPanel, float4( o.vPositionPs.xyz, 1.0 ) ).xyz;
			o.vPositionPs = Position3WsToPs( vPositionWs.xyz );
		}
		#endif

		o.vPositionPanelSpace = mul( instTransform, float4( inst.Rect.xy + corner * inst.Rect.zw, 0, 1 ) );
		o.vTexCoord.xy = corner;
		o.vTexCoord.zw = vPositionSs / vViewport.zw;

		float4 instColor = UnpackColor( inst.Color );
		o.vColor.rgb = SrgbGammaToLinear( instColor.rgb );
		o.vColor.a = instColor.a;

		o.iInstanceID = instanceIndex;

		return o;
	}
}

PS
{
	#include "common/blendmode.hlsl"

	// Scissor is now per-instance via ScissorIndex into ScissorBuffer (defined in COMMON)

	RenderState( SrgbWriteEnable0, true );
	RenderState( ColorWriteEnable0, RGBA );
	RenderState( FillMode, SOLID );
	RenderState( CullMode, NONE );
	RenderState( DepthWriteEnable, false );

	#if ( D_NO_ZTEST )
		RenderState( DepthEnable, false );
	#else
		RenderState( DepthEnable, true );
	#endif

	#define SUBPIXEL_AA_MAGIC 0.5

	float GetDistanceFromEdge( float2 pos, float2 size, float4 cornerRadius )
	{
		float minCorner = min( size.x, size.y );
		float4 r = min( cornerRadius * 2.0, minCorner );
		r.xy = ( pos.x > 0.0 ) ? r.xy : r.zw;
		r.x  = ( pos.y > 0.0 ) ? r.x  : r.y;
		float2 q = abs( pos ) - size + r.x;
		return -0.5 + min( max( q.x, q.y ), 0.0 ) + length( max( q, 0.0 ) ) - r.x;
	}

	float2 DistanceNormal( float2 p, float2 size, float4 cornerRadius )
	{
		const float eps = 1;
		const float2 h = float2( eps, 0 );
		return normalize( float3(
			GetDistanceFromEdge( p - h.xy, size, cornerRadius ) - GetDistanceFromEdge( p + h.xy, size, cornerRadius ),
			GetDistanceFromEdge( p - h.yx, size, cornerRadius ) - GetDistanceFromEdge( p + h.yx, size, cornerRadius ),
			2.0 * h.x
		) ).xy;
	}

	float4 AddBorder( float2 texCoord, float2 pos, float dist, float2 boxSize, float4 cornerRadius, float4 borderWidth, float4 bcL, float4 bcT, float4 bcR, float4 bcB )
	{
		float2 vTransPos = texCoord * boxSize;

		float2 fScale = 1.0 / ( 1.0 - ( float2( borderWidth.z + borderWidth.x, borderWidth.y + borderWidth.w ) / boxSize ) );
		vTransPos = ( vTransPos - ( boxSize * 0.5 ) ) * fScale + ( boxSize * 0.5 );
		vTransPos += float2( -borderWidth.x + borderWidth.z, -borderWidth.y + borderWidth.a ) * ( fScale * 0.5 );

		float2 vOffsetPos = boxSize * ( ( vTransPos / boxSize ) * 2.0 - 1.0 );
		float2 vNormal = DistanceNormal( vOffsetPos, boxSize, cornerRadius );
		float fDistance = GetDistanceFromEdge( vOffsetPos, boxSize, cornerRadius ) + 1.5;

		float4 vBorderL = bcL; vBorderL.a = max(  vNormal.x, 0 ) * fDistance / borderWidth.x;
		float4 vBorderT = bcT; vBorderT.a = max(  vNormal.y, 0 ) * fDistance / borderWidth.y;
		float4 vBorderR = bcR; vBorderR.a = max( -vNormal.x, 0 ) * fDistance / borderWidth.z;
		float4 vBorderB = bcB; vBorderB.a = max( -vNormal.y, 0 ) * fDistance / borderWidth.w;

		float4 vBorderColor = -100;
		float fBorderAlpha = 0;

		if ( borderWidth.x > 0 && vBorderL.a > vBorderColor.a ) { vBorderColor = vBorderL; fBorderAlpha = bcL.a; }
		if ( borderWidth.y > 0 && vBorderT.a > vBorderColor.a ) { vBorderColor = vBorderT; fBorderAlpha = bcT.a; }
		if ( borderWidth.z > 0 && vBorderR.a > vBorderColor.a ) { vBorderColor = vBorderR; fBorderAlpha = bcR.a; }
		if ( borderWidth.w > 0 && vBorderB.a > vBorderColor.a ) { vBorderColor = vBorderB; fBorderAlpha = bcB.a; }

		float fAntialiasAmount = max( 1.0 / SUBPIXEL_AA_MAGIC, 2.0 / SUBPIXEL_AA_MAGIC * abs( dist / min( boxSize.x, boxSize.y ) ) );
		vBorderColor.a = saturate( smoothstep( 0, fAntialiasAmount, fDistance ) ) * fBorderAlpha;

		return vBorderColor;
	}

	float4 AddImageBorder( float2 texCoord, float2 boxSize, float4 borderWidth, int borderImageIndex, int borderImageSamplerIndex, int borderImageMode, int borderImageFill, float4 borderImageSlice )
	{
		float4 BorderImageWidth = borderWidth;
		Texture2D borderTex = Bindless::GetTexture2D( borderImageIndex );
		float2 vBorderImageSize = TextureDimensions2D( borderTex, 0 );
		float4 vBorderPixelSize = borderImageSlice;
		float4 vBorderPixelRatio = vBorderPixelSize / float4( vBorderImageSize.x, vBorderImageSize.y, vBorderImageSize.x, vBorderImageSize.y );
		float2 vBoxTexCoord = texCoord * boxSize;
		float2 uv = 0.0;

		if ( !borderImageFill &&
			vBoxTexCoord.x > BorderImageWidth.x && vBoxTexCoord.x < boxSize.x - BorderImageWidth.z &&
			vBoxTexCoord.y > BorderImageWidth.y && vBoxTexCoord.y < boxSize.y - BorderImageWidth.w )
			return 0;

		if ( vBorderPixelSize.x < vBorderImageSize.x * 0.5 )
		{
			if ( borderImageMode == 1 )
			{
				float2 vMiddleSize = 1.0 - ( vBorderPixelRatio.xy + vBorderPixelRatio.zw );
				float2 vRepeatAmount = floor( ( boxSize * vMiddleSize ) / BorderImageWidth.xy );
				uv.x = ( vBoxTexCoord.x - BorderImageWidth.x ) / ( boxSize.x - ( BorderImageWidth.x + BorderImageWidth.z ) ) * vRepeatAmount.x;
				uv.x = fmod( uv.x, vMiddleSize.x ) + vBorderPixelRatio.x;
				uv.y = ( vBoxTexCoord.y - BorderImageWidth.y ) / ( boxSize.y - ( BorderImageWidth.y + BorderImageWidth.w ) ) * vRepeatAmount.y;
				uv.y = fmod( uv.y, vMiddleSize.y ) + vBorderPixelRatio.y;
			}
			else
			{
				uv.x = ( vBoxTexCoord.x - BorderImageWidth.x ) / ( boxSize.x - ( BorderImageWidth.x + BorderImageWidth.z ) );
				uv.x = uv.x * ( 1.0 - ( vBorderPixelRatio.x + vBorderPixelRatio.z ) ) + vBorderPixelRatio.x;
				uv.y = ( vBoxTexCoord.y - BorderImageWidth.y ) / ( boxSize.y - ( BorderImageWidth.y + BorderImageWidth.w ) );
				uv.y = uv.y * ( 1.0 - ( vBorderPixelRatio.y + vBorderPixelRatio.w ) ) + vBorderPixelRatio.y;
			}
		}

		if ( vBoxTexCoord.x < BorderImageWidth.x )
			uv.x = ( vBoxTexCoord.x / BorderImageWidth.x ) * vBorderPixelRatio.x;
		else if ( vBoxTexCoord.x > boxSize.x - BorderImageWidth.z )
			uv.x = ( ( vBoxTexCoord.x - ( boxSize.x - BorderImageWidth.z ) ) / BorderImageWidth.z ) * vBorderPixelRatio.z + ( 1.0 - vBorderPixelRatio.z );

		if ( vBoxTexCoord.y < BorderImageWidth.y )
			uv.y = ( vBoxTexCoord.y / BorderImageWidth.y ) * vBorderPixelRatio.y;
		else if ( vBoxTexCoord.y > boxSize.y - BorderImageWidth.w )
			uv.y = ( ( vBoxTexCoord.y - ( boxSize.y - BorderImageWidth.w ) ) / BorderImageWidth.w ) * vBorderPixelRatio.w + ( 1.0 - vBorderPixelRatio.w );

		float4 r = borderTex.Sample( Bindless::GetSampler( borderImageSamplerIndex ), uv );
		r.xyz = SrgbGammaToLinear( r.xyz );
		return r;
	}

	float4 AlphaBlend( float4 src, float4 dest )
	{
		float4 result;
		result.a = src.a + ( 1 - src.a ) * dest.a;
		result.rgb = ( 1 / result.a ) * ( src.a * src.rgb + ( 1 - src.a ) * dest.a * dest.rgb );
		return result;
	}

	float2 RotateTexCoord( float2 vTexCoord, float angle, float2 offset = 0.5 )
	{
		float2x2 m = float2x2( cos( angle ), -sin( angle ), sin( angle ), cos( angle ) );
		return mul( m, vTexCoord - offset ) + offset;
	}

	bool IsOutsideBox( float2 vPos, float4 vRect, float4 vRadius, float4x4 matTransform )
	{
		vPos = mul( matTransform, float4( vPos, 0, 1 ) ).xy;
		float2 tl = float2( vRect.x + vRadius.x, vRect.y + vRadius.x );
		float2 tr = float2( vRect.z - vRadius.y, vRect.y + vRadius.y );
		float2 bl = float2( vRect.x + vRadius.z, vRect.w - vRadius.z );
		float2 br = float2( vRect.z - vRadius.w, vRect.w - vRadius.w );

		return ( vPos.x < vRect.x || vPos.x > vRect.z || vPos.y > vRect.w || vPos.y < vRect.y ) ||
			   ( length( vPos - tl ) > vRadius.x && vPos.x < tl.x && vPos.y < tl.y ) ||
			   ( length( vPos - tr ) > vRadius.y && vPos.x > tr.x && vPos.y < tr.y ) ||
			   ( length( vPos - bl ) > vRadius.z && vPos.x < bl.x && vPos.y > bl.y ) ||
			   ( length( vPos - br ) > vRadius.w && vPos.x > br.x && vPos.y > br.y );
	}

	float ShadowRoundedRect( float2 pos, float2 center, float2 box, float size )
	{
		return size - length( pos - center );
	}

	float ShadowDrawCurvedRect( float2 pos, float2 size, float4 cornerRadius, float shadowWidth, bool inset )
	{
		float f = 1;
		f = min( pos.x, size.x - pos.x );
		f = min( f, pos.y );
		f = min( f, size.y - pos.y );

		float radAdd = shadowWidth * 0.4;
		if ( inset ) radAdd = -radAdd;

		float r = min( size.y * 0.5, cornerRadius[0] + radAdd );
		if ( pos.x < r && pos.y < r )
			f = min( f, ShadowRoundedRect( pos, r, size, r ) );

		r = min( size.y * 0.5, cornerRadius[1] + radAdd );
		if ( pos.x > size.x - r && pos.y < r )
			f = min( f, ShadowRoundedRect( pos, float2( size.x - r, r ), size, r ) );

		r = min( size.y * 0.5, cornerRadius[3] + radAdd );
		if ( pos.x > size.x - r && pos.y > size.y - r )
			f = min( f, ShadowRoundedRect( pos, float2( size.x - r, size.y - r ), size, r ) );

		r = min( size.y * 0.5, cornerRadius[2] + radAdd );
		if ( pos.x < r && pos.y > size.y - r )
			f = min( f, ShadowRoundedRect( pos, float2( r, size.y - r ), size, r ) );

		return f;
	}

	float4 RenderShadow( BoxInstanceData inst, PixelInput i, bool inset )
	{
		float blur = inst.BackgroundAngle;
		float spread = inst.BackgroundRect.x;
		float2 offset = inst.BackgroundRect.yz;
		float2 boxSize = inst.Rect.zw;

		// The rect was bloated by blur — compute inner shadow box size
		float2 shadowSize = boxSize - float2( blur, blur ) * 2.0;

		float2 pos = boxSize * i.vTexCoord.xy - float2( blur, blur );

		if ( inset ) pos -= offset;

		float d = ShadowDrawCurvedRect( pos, shadowSize, inst.BorderRadius, blur, inset );
		d = smoothstep( -blur * 0.5, blur * 0.5, d );
		d = saturate( d );

		if ( inset ) d = 1.0 - d;

		float4 col = i.vColor;
		col.a *= d;
		return col;
	}
	float OutlineDrawRoundedRect( float2 pos, float2 size, float4 cornerRadius )
	{
		float f = 1;
		f = min( pos.x, size.x - pos.x );
		f = min( f, pos.y );
		f = min( f, size.y - pos.y );

		float r = min( size.y * 0.5, cornerRadius[0] );
		if ( pos.x < r && pos.y < r )
			f = min( f, ShadowRoundedRect( pos, r, size, r ) );

		r = min( size.y * 0.5, cornerRadius[1] );
		if ( pos.x > size.x - r && pos.y < r )
			f = min( f, ShadowRoundedRect( pos, float2( size.x - r, r ), size, r ) );

		r = min( size.y * 0.5, cornerRadius[2] );
		if ( pos.x < r && pos.y > size.y - r )
			f = min( f, ShadowRoundedRect( pos, float2( r, size.y - r ), size, r ) );

		r = min( size.y * 0.5, cornerRadius[3] );
		if ( pos.x > size.x - r && pos.y > size.y - r )
			f = min( f, ShadowRoundedRect( pos, float2( size.x - r, size.y - r ), size, r ) );

		return f;
	}

	float4 RenderOutline( BoxInstanceData inst, PixelInput i )
	{
		float2 panelSize = inst.BackgroundRect.xy;
		float outlineWidth = inst.BackgroundRect.z;
		float outlineOffset = inst.BackgroundRect.w;
		float bloat = inst.BackgroundAngle;
		float2 boxSize = inst.Rect.zw;

		float2 pos = ( panelSize + float2( bloat, bloat ) * 2.0 ) * i.vTexCoord.xy - float2( bloat, bloat );
		float d = OutlineDrawRoundedRect( pos, panelSize, inst.BorderRadius );
		float dist_outside = -d;

		float inner_aa = smoothstep( outlineOffset - 0.25, outlineOffset + 0.25, dist_outside );
		float outer_aa = 1.0 - smoothstep( outlineOffset + outlineWidth - 0.5, outlineOffset + outlineWidth + 0.5, dist_outside );

		float4 col = i.vColor;
		col.a *= inner_aa * outer_aa;
		return col;
	}

	//
	// Where a pixel falls along the gradient, 0 at the first stop and 1 at the last.
	// Linear runs along a line through the box centre, long enough that its ends touch
	// the corners; radial and conic measure out from their centre - all matching the web.
	//
	float GradientPosition( GradientData g, float2 texCoord, float2 boxSize )
	{
		if ( g.Type == 0 ) // linear
		{
			float2 dir = float2( sin( g.Angle ), cos( g.Angle ) ); // 0 = down the panel, 90deg = right
			float2 rel = ( texCoord - 0.5 ) * boxSize;
			float len = abs( boxSize.x * dir.x ) + abs( boxSize.y * dir.y );
			return dot( rel, dir ) / max( len, 0.0001 ) + 0.5;
		}

		float2 p = texCoord * boxSize;

		float2 c;
		c.x = ( g.CenterUnits & 1 ) ? g.Center.x * boxSize.x : g.Center.x;
		c.y = ( g.CenterUnits & 2 ) ? g.Center.y * boxSize.y : g.Center.y;

		float2 d = p - c;

		if ( g.Type == 2 ) // conic
		{
			// Zero points straight up and the sweep runs clockwise, like the web. Angle
			// rotates where it starts. frac wraps the negative half back into 0..1.
			float a = atan2( d.x, -d.y );
			return frac( ( a - g.Angle ) / 6.28318530718 );
		}

		// radial - the ending shape's radii, per the four CSS sizes
		float2 nearSide = float2( min( c.x, boxSize.x - c.x ), min( c.y, boxSize.y - c.y ) );
		float2 farSide = float2( max( c.x, boxSize.x - c.x ), max( c.y, boxSize.y - c.y ) );

		float2 radius;

		if ( g.Circle )
		{
			// One radius: the nearest/farthest side, or the distance to that corner.
			float r =	( g.SizeMode == 0 ) ? max( farSide.x, farSide.y ) :
						( g.SizeMode == 1 ) ? length( farSide ) :
						( g.SizeMode == 2 ) ? min( nearSide.x, nearSide.y ) :
						length( nearSide );

			radius = float2( r, r );
		}
		else
		{
			// A corner ellipse keeps the matching side ellipse's aspect and is scaled to
			// touch the corner, which always works out to sqrt(2) larger.
			radius =	( g.SizeMode == 0 ) ? farSide :
						( g.SizeMode == 1 ) ? farSide * 1.41421356 :
						( g.SizeMode == 2 ) ? nearSide :
						nearSide * 1.41421356;
		}

		return length( d / max( radius, 0.0001 ) );
	}

	//
	// Stops interpolate premultiplied with linear alpha, in sRGB space, like the web.
	//
	float4 EvaluateGradient( GradientData g, float2 texCoord, float2 boxSize )
	{
		float t = GradientPosition( g, texCoord, boxSize );

		int last = g.Count - 1;

		if ( t <= g.StopOffsets[0] )
			return g.StopColors[0];

		if ( t >= g.StopOffsets[last] )
			return g.StopColors[last];

		float4 col = g.StopColors[last];

		[loop]
		for ( int s = 0; s < last; s++ )
		{
			float o1 = g.StopOffsets[s + 1];
			if ( t <= o1 )
			{
				float o0 = g.StopOffsets[s];
				float f = saturate( ( t - o0 ) / max( o1 - o0, 0.0001 ) );

				float4 A = g.StopColors[s];
				float4 B = g.StopColors[s + 1];

				float a = lerp( A.a, B.a, f );
				float3 rgb = lerp( A.rgb * A.a, B.rgb * B.a, f );
				if ( a > 0.0001 )
					rgb /= a;

				col = float4( rgb, a );
				break;
			}
		}

		return col;
	}

	float4 MainPs( PixelInput i ) : SV_Target0
	{
		BoxInstanceData inst = BoxInstances[i.iInstanceID];

		// Per-instance scissoring via lookup table. Must run before mode dispatch so shadows/outlines also get clipped.
		if ( inst.ScissorIndex >= 0 )
		{
			ScissorData scissor = ScissorBuffer[inst.ScissorIndex];
			float2 pixelPos = i.vPositionPanelSpace.xy;
			bool outside = IsOutsideBox( pixelPos, scissor.Rect, scissor.CornerRadius, scissor.TransformMat );
			bool shouldClip = scissor.Invert ? !outside : outside;
			clip( shouldClip ? -1 : 1 );
		}

		// Second scissor slot (used by outset box-shadows to clip inside the panel rect)
		if ( inst.InverseScissorIndex >= 0 )
		{
			ScissorData scissor = ScissorBuffer[inst.InverseScissorIndex];
			float2 pixelPos = i.vPositionPanelSpace.xy;
			bool outside = IsOutsideBox( pixelPos, scissor.Rect, scissor.CornerRadius, scissor.TransformMat );
			bool shouldClip = scissor.Invert ? !outside : outside;
			clip( shouldClip ? -1 : 1 );
		}

		if ( inst.Mode == 1 ) return RenderShadow( inst, i, false );
		if ( inst.Mode == 2 ) return RenderShadow( inst, i, true );
		if ( inst.Mode == 3 ) return RenderOutline( inst, i );

		// Mode 0: standard box rendering
		float2 boxSize = inst.Rect.zw;
		float4 cornerRadius = inst.BorderRadius;
		float4 borderWidth = inst.BorderSize;

		float2 pos = boxSize * ( i.vTexCoord.xy * 2.0 - 1.0 );
		float dist = GetDistanceFromEdge( pos, boxSize, cornerRadius );

		float4 col = i.vColor;

		// Background image or gradient (negative TextureIndex = gradient table index).
		// Both are tiles sized and placed by background-size/position, like the web.
		if ( inst.TextureIndex != 0 )
		{
			float2 bgSize = inst.BackgroundRect.zw;
			float4 bgTint = UnpackColor( inst.BackgroundTint );
			bgTint.rgb = SrgbGammaToLinear( bgTint.rgb );

			float2 vOffset = inst.BackgroundRect.xy / bgSize;
			float2 vUV = -vOffset + ( i.vTexCoord.xy * ( boxSize / bgSize ) );

			float4 vImage;
			int bgRepeat = inst.BackgroundRepeat;

			if ( inst.TextureIndex > 0 )
			{
				vUV = RotateTexCoord( vUV, inst.BackgroundAngle );

				Texture2D tex = Bindless::GetTexture2D( inst.TextureIndex );
				vImage = tex.SampleBias( Bindless::GetSampler( inst.SamplerIndex ), vUV, -1.5 );
			}
			else
			{
				// The sampler wraps textures; wrap the tile coordinate ourselves.
				// Clamping falls out of the stop walk, which pins to the end stops.
				float2 tileUV = vUV;
				if ( bgRepeat == 0 || bgRepeat == 1 ) tileUV.x = frac( tileUV.x );
				if ( bgRepeat == 0 || bgRepeat == 2 ) tileUV.y = frac( tileUV.y );

				GradientData gradient = GradientBuffer[ -inst.TextureIndex - 1 ];
				vImage = EvaluateGradient( gradient, tileUV, bgSize );
			}

			if ( bgRepeat != 0 && bgRepeat != 4 )
			{
				if ( bgRepeat != 1 )
					if ( vUV.x < 0 || vUV.x > 1 ) vImage = 0;
				if ( bgRepeat != 2 )
					if ( vUV.y < 0 || vUV.y > 1 ) vImage = 0;
			}

			vImage.xyz = SrgbGammaToLinear( vImage.xyz );

			#if ( D_BLENDMODE == 3 )
				vImage.rgb *= bgTint.rgb;
				vImage *= bgTint.a;
			#else
				vImage *= bgTint;
			#endif

			col.rgb = lerp( col.rgb, vImage.rgb, saturate( vImage.a + ( 1 - col.a ) ) );
			col.a = max( col.a, vImage.a );
		}

		// Border image or solid border
		if ( inst.BorderImageMode > 0 )
		{
			float4 biTint = UnpackColor( inst.BorderImageTint );
			biTint.rgb = SrgbGammaToLinear( biTint.rgb );
			float4 vBoxBorder = AddImageBorder( i.vTexCoord.xy, boxSize, borderWidth, inst.BorderImageIndex,
				inst.BorderImageSamplerIndex, inst.BorderImageMode, inst.BorderImageFill, inst.BorderImageSlice ) * biTint;
			col = AlphaBlend( vBoxBorder, col );
		}
		else
		{
			bool hasBorder = borderWidth.x != 0 || borderWidth.y != 0 || borderWidth.z != 0 || borderWidth.w != 0;
			if ( hasBorder )
			{
				float4 vBoxBorder = AddBorder( i.vTexCoord.xy, pos, dist, boxSize, cornerRadius, borderWidth,
					UnpackColor( inst.BorderColorL ), UnpackColor( inst.BorderColorT ),
					UnpackColor( inst.BorderColorR ), UnpackColor( inst.BorderColorB ) );
				vBoxBorder.xyz = SrgbGammaToLinear( vBoxBorder.xyz );
				col = AlphaBlend( vBoxBorder, col );
			}
		}

		float edge = saturate( -dist - 0.5 );

		if ( inst.Flags & 1 )
		{
			col *= edge;
		}
		else
		{
			col.a *= edge;
		}

		return col;
	}
}
