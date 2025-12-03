namespace Editor;

[CustomEditor( typeof( string ), NamedEditor = "package:games" )]
public class GamesPackageControlWidget : ControlWidget
{
	public List<Package> CurrentPackages { get; set; } = [];
	private Package FirstPackage => CurrentPackages.FirstOrDefault();
	public override bool IsControlButton => !IsControlDisabled;

	private void Load( string idents ) {		
		if ( !string.IsNullOrEmpty( idents ) )
		{
			foreach (var i in idents.Split(';')) {
				AddPackageFromIdent(i);
			}
		}
	}

	public GamesPackageControlWidget( SerializedProperty property ) : base( property )
	{
		HorizontalSizeMode = SizeMode.CanGrow | SizeMode.Expand;
		Cursor = CursorShape.Finger;
		MouseTracking = true;

		var idents = property.GetValue<string>( null );
		Load(idents);
	}

	protected override void PaintControl()
	{
		var rect = new Rect( 0, Size );

		var iconRect = rect.Shrink( 3 );
		iconRect.Width = iconRect.Height;

		rect.Left = iconRect.Right + 10;

		Paint.ClearPen();
		Paint.SetBrush( Theme.SurfaceBackground.WithAlpha( 0.2f ) );
		Paint.DrawRect( iconRect, 2 );

		var alpha = IsControlDisabled ? 0.6f : 1f;

		var textRect = rect.Grow( 4, 1, 0, 0 );
		if ( SerializedProperty.IsMultipleDifferentValues )
		{
			Paint.Draw( iconRect, FirstPackage?.Thumb );

			Paint.SetDefaultFont();
			Paint.SetPen( Theme.MultipleValues.WithAlpha( alpha ) );
			Paint.DrawText( textRect, $"Multiple Values", TextFlag.LeftCenter );
		}
		else
		{
			Paint.Draw( iconRect, FirstPackage?.Thumb );

			Paint.SetDefaultFont();
			Paint.SetPen( Theme.TextControl.WithAlpha( alpha ) );
			Paint.DrawText( textRect, FirstPackage?.Title ?? "No package selected...", TextFlag.LeftCenter );
		}
	}

	protected override void OnMouseClick( MouseEvent e )
	{
		base.OnMouseClick( e );

		if ( ReadOnly ) return;

		PropertyStartEdit();

		var picker = new PackageSelector( this, "type:game", ( packages ) =>
		{
			CurrentPackages = [];

			List<string> idents = [];
			foreach (var package in packages) {
				var ident = package.FullIdent;
				idents.Add(ident);

				AddPackageFromIdent(ident);
			}

			SerializedProperty.SetValue( string.Join(";", idents) );

			PropertyFinishEdit();
		}, CurrentPackages.ToArray() );
		picker.MultiSelect = true;
		picker.WindowTitle = $"Select {SerializedProperty.DisplayName}";
		picker.Show();
	}

	protected override void OnContextMenu( ContextMenuEvent e )
	{
		var m = new ContextMenu();

		var idents = SerializedProperty.GetValue<string>( null );

		m.AddOption( "Copy", "file_copy", action: Copy ).Enabled = !string.IsNullOrEmpty( idents );
		m.AddOption( "Paste", "content_paste", action: Paste );
		m.AddSeparator();
		m.AddOption( "Clear", "backspace", action: Clear ).Enabled = !string.IsNullOrEmpty( idents );

		m.OpenAtCursor( false );
		e.Accepted = true;
	}

	void Copy()
	{
		var idents = SerializedProperty.GetValue<string>( null );
		if ( idents == null ) return;

		EditorUtility.Clipboard.Copy( idents );
	}

	void Paste()
	{
		CurrentPackages = [];

		var idents = EditorUtility.Clipboard.Paste();
		Load(idents);

		SerializedProperty.SetValue( string.Join(";", idents) );
	}

	void Clear()
	{
		SerializedProperty.SetValue( (string)null );
		CurrentPackages = [];
	}

	async void AddPackageFromIdent( string ident )
	{
		var package = await Package.Fetch( ident, true );
		CurrentPackages.Add(package);
	}
}
