using Sandbox.Rendering;
using System.Runtime.InteropServices;

namespace Sandbox.UI;

/// <summary>
/// Per-box data uploaded to a StructuredBuffer for the batched UI box shader.
/// Must match BoxInstanceData in ui_cssbox_batched.shader.
/// </summary>
[StructLayout( LayoutKind.Sequential )]
struct GPUBoxInstance
{
	public Vector4 Rect;
	public uint Color;
	public Vector4 BorderRadius;
	public Vector4 BorderSize;
	public uint BorderColorL;
	public uint BorderColorT;
	public uint BorderColorR;
	public uint BorderColorB;
	public int TextureIndex;
	public int SamplerIndex;
	public int BackgroundRepeat;
	public float BackgroundAngle;
	public Vector4 BackgroundRect;
	public uint BackgroundTint;
	public int BorderImageIndex;
	public int BorderImageSamplerIndex;
	public int BorderImageMode;
	public int BorderImageFill;
	public Vector4 BorderImageSlice;
	public uint BorderImageTint;
	public int Flags;
	public int ScissorIndex;
	public int Mode;
	public int TransformIndex;
	public int InverseScissorIndex;

	// Mode 1/2 (shadow): BackgroundAngle = blur, BackgroundRect = (spread, offset.x, offset.y, 0)
	//                     BorderSize = inverse scissor rect (for outset clipping)
	//                     BorderColorL = inverse scissor corner radius (packed)
	// Mode 3 (outline):   BackgroundAngle = width, BackgroundRect.x = offset

	internal static GPUBoxInstance FromShadow( in ShadowDrawDescriptor desc )
	{
		var shadowRect = desc.Inset ? desc.PanelRect : desc.PanelRect + desc.Offset;
		shadowRect = shadowRect.Grow( desc.Spread );
		var bloatedRect = shadowRect.Grow( desc.Blur );

		return new GPUBoxInstance
		{
			Rect = new Vector4( bloatedRect.Left, bloatedRect.Top, bloatedRect.Width, bloatedRect.Height ),
			Color = desc.Color.RawInt,
			BorderRadius = desc.BorderRadius,
			BackgroundAngle = desc.Blur,
			BackgroundRect = new Vector4( desc.Spread, desc.Offset.x, desc.Offset.y, 0 ),
			Mode = desc.Inset ? 2 : 1,
			InverseScissorIndex = -1,
		};
	}

	internal static GPUBoxInstance FromOutline( in OutlineDrawDescriptor desc )
	{
		var outwardExtent = MathF.Max( desc.Offset + desc.Width, 0f );
		var bloat = outwardExtent + 1.0f;
		var bloatedRect = desc.PanelRect.Grow( bloat );

		return new GPUBoxInstance
		{
			Rect = new Vector4( bloatedRect.Left, bloatedRect.Top, bloatedRect.Width, bloatedRect.Height ),
			Color = desc.Color.RawInt,
			BorderRadius = desc.BorderRadius,
			BackgroundRect = new Vector4( desc.PanelRect.Width, desc.PanelRect.Height, desc.Width, desc.Offset ),
			BackgroundAngle = bloat,
			Mode = 3,
			InverseScissorIndex = -1,
		};
	}

	internal static GPUBoxInstance From( in BoxDrawDescriptor desc )
	{
		var hasImage = desc.BackgroundImage != null && desc.BackgroundImage != Texture.Invalid;
		var hasBorderImage = desc.BorderImageTexture != null;

		var bgRect = hasImage || desc.HasGradient
			? (desc.BackgroundRect.z > 0 || desc.BackgroundRect.w > 0
				? desc.BackgroundRect
				: new Vector4( 0, 0, desc.PanelRect.Width, desc.PanelRect.Height ))
			: Vector4.Zero;

		var bgTint = hasImage || desc.HasGradient
			? desc.BackgroundTint
			: new Color( 0, 0, 0, 0 );

		return new GPUBoxInstance
		{
			Rect = new Vector4( desc.PanelRect.Left, desc.PanelRect.Top, desc.PanelRect.Width, desc.PanelRect.Height ),
			Color = desc.Color.RawInt,
			BorderRadius = desc.BorderRadius,
			BorderSize = desc.BorderSize,
			BorderColorL = desc.BorderColorL.RawInt,
			BorderColorT = desc.BorderColorT.RawInt,
			BorderColorR = desc.BorderColorR.RawInt,
			BorderColorB = desc.BorderColorB.RawInt,
			TextureIndex = hasImage ? desc.BackgroundImage.Index : 0,
			SamplerIndex = GetSamplerIndex( desc.BackgroundRepeat, desc.FilterMode ),
			BackgroundRepeat = (int)desc.BackgroundRepeat,
			BackgroundAngle = desc.BackgroundAngle,
			BackgroundRect = bgRect,
			BackgroundTint = bgTint.RawInt,
			BorderImageIndex = hasBorderImage ? desc.BorderImageTexture.Index : 0,
			BorderImageSamplerIndex = GetClampSamplerIndex( desc.FilterMode ),
			BorderImageMode = hasBorderImage ? (desc.BorderImageRepeat == UI.BorderImageRepeat.Stretch ? 2 : 1) : 0,
			BorderImageFill = hasBorderImage && desc.BorderImageFill == UI.BorderImageFill.Filled ? 1 : 0,
			BorderImageSlice = desc.BorderImageSlice,
			BorderImageTint = hasBorderImage ? desc.BorderImageTint.RawInt : 0,
			Flags = desc.PremultiplyAlpha ? 1 : 0,
			InverseScissorIndex = -1,
		};
	}

	static int GetSamplerIndex( UI.BackgroundRepeat repeat, FilterMode filter )
	{
		var sampler = repeat switch
		{
			UI.BackgroundRepeat.RepeatX => new SamplerState { AddressModeV = TextureAddressMode.Clamp, Filter = filter },
			UI.BackgroundRepeat.RepeatY => new SamplerState { AddressModeU = TextureAddressMode.Clamp, Filter = filter },
			UI.BackgroundRepeat.NoRepeat => new SamplerState { AddressModeU = TextureAddressMode.Border, AddressModeV = TextureAddressMode.Border, Filter = filter },
			UI.BackgroundRepeat.Clamp => new SamplerState { AddressModeU = TextureAddressMode.Clamp, AddressModeV = TextureAddressMode.Clamp, Filter = filter },
			_ => new SamplerState { Filter = filter }
		};

		return SamplerState.GetBindlessIndex( sampler );
	}

	static int GetClampSamplerIndex( FilterMode filter )
	{
		return SamplerState.GetBindlessIndex( new SamplerState
		{
			AddressModeU = TextureAddressMode.Clamp,
			AddressModeV = TextureAddressMode.Clamp,
			Filter = filter
		} );
	}
}

[System.Runtime.CompilerServices.InlineArray( GradientInfo.MaxStops )]
internal struct GradientStopColors
{
	Color _element;
}

[System.Runtime.CompilerServices.InlineArray( GradientInfo.MaxStops )]
internal struct GradientStopOffsets
{
	float _element;
}

/// <summary>
/// Per-gradient data uploaded to a StructuredBuffer for shader-evaluated background
/// gradients. Must match GradientData in ui_cssbox_batched.shader. Colors are straight
/// alpha in sRGB space, exactly as authored; Angle is radians, 0 pointing down the panel
/// for linear and straight up for conic.
/// </summary>
[StructLayout( LayoutKind.Sequential )]
internal struct GPUGradientInstance
{
	/// <summary>Bit per axis, set when that centre component is a fraction of the box rather than pixels.</summary>
	const int CenterXIsFraction = 1;
	const int CenterYIsFraction = 2;

	public GradientStopColors StopColors;
	public GradientStopOffsets StopOffsets;
	public int Count;
	public float Angle;
	public int Type;
	public int SizeMode;
	public Vector2 Center;
	public int CenterUnits;
	public int Circle;

	internal static GPUGradientInstance From( in GradientInfo gradient )
	{
		var stops = gradient.ColorOffsets;
		var count = Math.Min( stops.Length, GradientInfo.MaxStops );

		var inst = new GPUGradientInstance
		{
			Count = count,
			Angle = gradient.Angle,
			Type = (int)gradient.GradientType,
			SizeMode = (int)gradient.SizeMode,
			Circle = gradient.Circle ? 1 : 0,
		};

		// The box size only exists in the shader, so percentages travel as a fraction
		// with a flag and get resolved there.
		inst.Center = new Vector2( CenterValue( gradient.OffsetX ), CenterValue( gradient.OffsetY ) );

		if ( IsFraction( gradient.OffsetX ) ) inst.CenterUnits |= CenterXIsFraction;
		if ( IsFraction( gradient.OffsetY ) ) inst.CenterUnits |= CenterYIsFraction;

		for ( int i = 0; i < count; i++ )
		{
			inst.StopColors[i] = stops[i].color;
			inst.StopOffsets[i] = stops[i].offset ?? 0f;
		}

		return inst;
	}

	static bool IsFraction( Length length ) => length.Unit != LengthUnit.Pixels;

	static float CenterValue( Length length )
	{
		// GetPixels against a parent of 1 turns a percentage into its fraction and
		// leaves a pixel length alone.
		return length.GetPixels( 1f );
	}
}

/// <summary>
/// Per-scissor data uploaded to a StructuredBuffer for per-instance clipping.
/// Must match ScissorData in ui_cssbox_batched.shader.
/// </summary>
[StructLayout( LayoutKind.Sequential )]
internal struct ScissorInstance
{
	public Vector4 Rect;
	public Vector4 CornerRadius;
	public Matrix TransformMat;
	public int Invert;
}

/// <summary>
/// Per-transform data uploaded to a StructuredBuffer for per-instance transforms.
/// Must match TransformData in ui_cssbox_batched.shader.
/// </summary>
[StructLayout( LayoutKind.Sequential )]
internal struct TransformInstance
{
	public Matrix Mat;
}
