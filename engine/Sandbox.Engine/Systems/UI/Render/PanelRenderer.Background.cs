using Sandbox.Rendering;

namespace Sandbox.UI;

partial class PanelRenderer
{
	private void AddBackgroundDescriptor( Panel panel, ref RenderState state, RenderLayer target )
	{
		if ( panel.HasBackground && panel.ComputedStyle is { } style )
		{
			panel.BackgroundBlendMode = ParseBlendMode( style.BackgroundBlendMode );

			var opacity = state.RenderOpacity;
			var desc = CreateBoxDescriptor( panel, style, opacity );
			desc.BackgroundBlendMode = panel.BackgroundBlendMode;
			desc.BackgroundGradient = style.BackgroundGradient;

			var texture = style.BackgroundImage;
			if ( texture is not null && texture != Texture.Invalid )
			{
				desc.BackgroundImage = texture;
				desc.BackgroundRect = ImageRect.Calculate( new ImageRect.Input
				{
					ScaleToScreen = panel.ScaleToScreen,
					Image = texture,
					PanelRect = panel.Box.Rect,
					DefaultSize = Length.Auto,
					ImagePositionX = style.BackgroundPositionX,
					ImagePositionY = style.BackgroundPositionY,
					ImageSizeX = style.BackgroundSizeX,
					ImageSizeY = style.BackgroundSizeY,
				} ).Rect;

				if ( texture.IsDirty )
					texture.IsDirty = false;
			}
			else if ( desc.HasGradient )
			{
				// Gradients have no intrinsic size - background-size/position apply to
				// their tile like the web, sized to the panel by default.
				desc.BackgroundRect = ImageRect.Calculate( new ImageRect.Input
				{
					ScaleToScreen = panel.ScaleToScreen,
					Image = null,
					PanelRect = panel.Box.Rect,
					DefaultSize = Length.Auto,
					ImagePositionX = style.BackgroundPositionX,
					ImagePositionY = style.BackgroundPositionY,
					ImageSizeX = style.BackgroundSizeX,
					ImageSizeY = style.BackgroundSizeY,
				} ).Rect;
			}

			target.AddBox( desc );
		}
	}
}
