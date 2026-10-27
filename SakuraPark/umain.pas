unit umain;

{ Sakura Lake Park - a pixel-art park drawn with BGRABitmap.

  Left: the scene, painted at 224 x 224 "art pixels" into a TBGRABitmap and
  stretched x3 without smoothing (rmSimpleStretch) for the pixel-art look.
  The terrain, cliffs, trees and buildings are generated from a seed once
  (FStatic); boats, visitors, petals, clouds and the day/night tint are drawn
  on a copy every frame (FFrame).
  Right: a control panel drawn with BGRABitmap antialiasing (cards, segmented
  buttons, switches, steppers, a bar chart) with its own hit testing.

  Command line: --seed=N --mode=0..3 (day, sunset, night, auto) --hour=H
                --snapshot=file.png --after=seconds  (save one frame, close) }

{$mode objfpc}{$H+}{$Q-}{$R-}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, ExtCtrls, LCLType,
  BGRABitmap, BGRABitmapTypes;

const
  SW = 224;              // scene size in art pixels
  SH = 224;
  PX = 3;                // screen pixels per art pixel
  PANEL_W = 340;
  CLIFF_H = 6;
  MAX_WALKERS = 64;
  MAX_BOATS = 16;
  MAX_PETALS = 300;

  ID_MODE = 1;           // 1..4: Day, Sunset, Night, Auto
  ID_TOGGLE = 10;        // 10..13: petals, clouds, sparkle, visitors
  ID_BOAT_DEC = 20;
  ID_BOAT_INC = 21;
  ID_VIS_DEC = 22;
  ID_VIS_INC = 23;
  ID_NEW = 30;
  ID_SAVE = 31;

type
  TTile = (tGrass, tWater, tPath, tBridge, tRock, tSolid);
  TTiles = set of TTile;

  TSpriteKind = (skRound, skPine, skSakura, skTorii, skPagoda, skTeaHouse,
    skLamp, skStoneLantern);

  TSprite = record
    Kind: TSpriteKind;
    X, Y, Size: Integer;
  end;

  TBoat = record
    X, Y, Dir, Speed: Double;
    Kind: Integer;
  end;

  TWalker = record
    Pos, Speed: Double;
    Lane, Pause: Integer;
    Shirt: TBGRAPixel;
    Parasol: Boolean;
  end;

  TPetal = record
    X, Y, VX, VY: Double;
    Life: Integer;
    Light: Boolean;
  end;

  TCloud = record
    X, Y, Speed: Double;
    DX, DY, R: array[0..5] of Integer;
  end;

  TBird = record
    X, Y, VX: Double;
  end;

  TLight = record
    X, Y: Integer;
    Glow: Boolean;
  end;

  TSparkle = record
    X, Y: Integer;
    Phase, Speed: Double;
  end;

  TUIItem = record
    R: TRect;
    Id: Integer;
  end;

  { TMainForm }

  TMainForm = class(TForm)
  private
    FTiles: array[0..SW - 1, 0..SH - 1] of TTile;
    FDepth: array[0..SW - 1, 0..SH - 1] of Byte;
    FOcc: array[0..SW - 1, 0..SH - 1] of Boolean;
    FStatic, FFrame, FBack: TBGRABitmap;
    FTimer: TTimer;
    FSeed, FTick: Integer;
    FLakeX, FLakeY: Integer;
    FSprites: array of TSprite;
    FRing: array of TPoint;
    FBoats: array of TBoat;
    FWalkers: array of TWalker;
    FPetals: array of TPetal;
    FClouds: array of TCloud;
    FBirds: array of TBird;
    FLights: array of TLight;
    FSparkles: array of TSparkle;
    FItems: array of TUIItem;
    FHover: Integer;
    FMode: Integer;
    FClock: Double;
    FShow: array[0..3] of Boolean;   // petals, clouds, sparkle, visitors
    FVisitorTarget: Integer;
    FFps: Double;
    FFpsFrames: Integer;
    FFpsTime: QWord;
    FToast: string;
    FToastUntil: Integer;
    FSnapFile: string;
    FSnapFrames: Integer;
    // terrain generation
    function TileAt(X, Y: Integer): TTile;
    function BoxIs(X1, Y1, X2, Y2: Integer; Allowed: TTiles): Boolean;
    procedure TileEllipse(CX, CY, RX, RY: Integer; T: TTile);
    procedure TileRiver(X1, Y1, X2, Y2, R: Integer);
    procedure MarkPath(X, Y: Integer);
    procedure TilePath(X1, Y1, X2, Y2: Integer);
    function RingAt(A: Double): TPoint;
    function WaterDist(X, Y: Integer): Integer;
    procedure AddSprite(K: TSpriteKind; X, Y, Size: Integer);
    procedure AddLight(X, Y: Integer; Glow: Boolean);
    procedure BuildScene;
    procedure PaintTiles;
    procedure DrawSprite(const S: TSprite);
    procedure DrawShadow(const S: TSprite);
    // life
    function CanBoat(X, Y: Double): Boolean;
    procedure AddBoat(X, Y: Double);
    procedure AddBoatRandom;
    procedure NewCloud(var C: TCloud; X: Double);
    procedure InitLife;
    function Hour: Double;
    function ActiveWalkers: Integer;
    procedure Step;
    // rendering
    procedure RenderScene;
    procedure RenderPanel;
    procedure RenderAll;
    procedure SetFont(Size: Integer; Bold: Boolean);
    procedure AddItem(X1, Y1, X2, Y2, Id: Integer);
    function ItemAt(X, Y: Integer): Integer;
    procedure HandleItem(Id: Integer);
    procedure ShowToast(const S: string);
    procedure TimerTick(Sender: TObject);
  protected
    procedure Paint; override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure EraseBackground(DC: HDC); override;
  end;

var
  MainForm: TMainForm;

implementation

const
  MODE_NAMES: array[0..3] of string = ('Day', 'Sunset', 'Night', 'Auto');
  TOGGLE_NAMES: array[0..3] of string =
    ('Cherry petals', 'Clouds & birds', 'Water sparkle', 'Visitors');

  SWAN: array[0..6] of string[9] = (
    '......WW.',
    '......WWO',
    '.......W.',
    '.W.....W.',
    'WWWPPPWWW',
    'WWWWWWWWW',
    '.SSSSSSS.');
  ROWBOAT: array[0..6] of string[9] = (
    '.........',
    '.........',
    '....H....',
    '....B....',
    'RNNNNNNNR',
    '..DDDDD..',
    '.........');

{ ---- pixel helpers ---- }

function RGBc(V: LongWord; A: Byte = 255): TBGRAPixel;
begin
  Result := BGRA((V shr 16) and $FF, (V shr 8) and $FF, V and $FF, A);
end;

function Hash(X, Y, S: Integer): LongWord;
var
  H: LongWord;
begin
  H := LongWord(X) * 374761393 + LongWord(Y) * 668265263 + LongWord(S) * 1103515245;
  H := (H xor (H shr 13)) * 1274126177;
  Result := H xor (H shr 16);
end;

procedure PutPx(B: TBGRABitmap; X, Y: Integer; C: TBGRAPixel);
begin
  if (X >= 0) and (Y >= 0) and (X < B.Width) and (Y < B.Height) then
    B.SetPixel(X, Y, C);
end;

procedure BlendPx(B: TBGRABitmap; X, Y: Integer; C: TBGRAPixel);
begin
  if (X >= 0) and (Y >= 0) and (X < B.Width) and (Y < B.Height) then
    B.DrawPixel(X, Y, C);
end;

procedure HLine(B: TBGRABitmap; X1, X2, Y: Integer; C: TBGRAPixel);
var
  X: Integer;
begin
  for X := X1 to X2 do
    PutPx(B, X, Y, C);
end;

procedure Box(B: TBGRABitmap; X1, Y1, X2, Y2: Integer; C: TBGRAPixel);
var
  Y: Integer;
begin
  for Y := Y1 to Y2 do
    HLine(B, X1, X2, Y, C);
end;

procedure Disc(B: TBGRABitmap; CX, CY: Integer; R: Double; C: TBGRAPixel;
  Blend: Boolean = False);
var
  DX, DY, N: Integer;
begin
  N := Trunc(R) + 1;
  for DY := -N to N do
    for DX := -N to N do
      if DX * DX + DY * DY <= R * R + R * 0.6 then
        if Blend then BlendPx(B, CX + DX, CY + DY, C)
        else PutPx(B, CX + DX, CY + DY, C);
end;

procedure ShadowEllipse(B: TBGRABitmap; CX, CY, RX, RY: Integer);
var
  DX, DY: Integer;
begin
  for DY := -RY to RY do
    for DX := -RX to RX do
      if Sqr(DX / (RX + 0.5)) + Sqr(DY / (RY + 0.5)) <= 1 then
        BlendPx(B, CX + DX, CY + DY, BGRA(20, 30, 50, 55));
end;

function ShirtColor(I: Integer): TBGRAPixel;
begin
  case I of
    0: Result := RGBc($D94A3A);
    1: Result := RGBc($3E6FD0);
    2: Result := RGBc($F2C94C);
    3: Result := RGBc($FFFFFF);
    4: Result := RGBc($8E5BC8);
    5: Result := RGBc($3FA36B);
  else
    Result := RGBc($F29BBF);
  end;
end;

function ArtColor(Ch: Char): TBGRAPixel;
begin
  case Ch of
    'W': Result := RGBc($FBFBFF);
    'O': Result := RGBc($F08A3C);
    'P': Result := RGBc($E77FA6);
    'S': Result := RGBc($B8C4DA);
    'H': Result := RGBc($F2C9A0);
    'B': Result := RGBc($3E6FD0);
    'N': Result := RGBc($9A6440);
    'D': Result := RGBc($6A4028);
    'R': Result := RGBc($5A3A22);
  else
    Result := BGRAPixelTransparent;
  end;
end;

function Crowd(H: Double): Double;
begin
  Result := 0.12 + 0.88 * Exp(-Sqr((H - 14) / 4.5));
end;

// how much "night" and "dusk" there is at hour H (0..1 each)
procedure TimeLight(H: Double; out Night, Dusk: Double);
begin
  if H < 5 then Night := 1
  else if H < 7 then Night := 1 - (H - 5) / 2
  else if H < 17.5 then Night := 0
  else if H < 20.5 then Night := (H - 17.5) / 3
  else Night := 1;
  Dusk := Max(0, 1 - Abs(H - 18.3) / 1.7);
  Dusk := Max(Dusk, 0.6 * Max(0, 1 - Abs(H - 6.2) / 1.2));
end;

{ ---- TMainForm: terrain ---- }

function TMainForm.TileAt(X, Y: Integer): TTile;
begin
  if (X < 0) or (Y < 0) or (X >= SW) or (Y >= SH) then
    Result := tGrass
  else
    Result := FTiles[X, Y];
end;

function TMainForm.BoxIs(X1, Y1, X2, Y2: Integer; Allowed: TTiles): Boolean;
var
  X, Y: Integer;
begin
  for Y := Y1 to Y2 do
    for X := X1 to X2 do
      if (X < 0) or (Y < 0) or (X >= SW) or (Y >= SH) or
         not (FTiles[X, Y] in Allowed) then
        Exit(False);
  Result := True;
end;

procedure TMainForm.TileEllipse(CX, CY, RX, RY: Integer; T: TTile);
var
  X, Y: Integer;
begin
  if (RX < 1) or (RY < 1) then Exit;
  for Y := CY - RY to CY + RY do
    for X := CX - RX to CX + RX do
      if (X >= 0) and (Y >= 0) and (X < SW) and (Y < SH) and
         (Sqr((X - CX) / RX) + Sqr((Y - CY) / RY) <= 1) then
        FTiles[X, Y] := T;
end;

// a winding river from (X1,Y1) to (X2,Y2)
procedure TMainForm.TileRiver(X1, Y1, X2, Y2, R: Integer);
var
  I, N, W: Integer;
  T, Len, NX, NY, Ph, Off: Double;
begin
  Len := Hypot(X2 - X1, Y2 - Y1);
  N := Round(Len);
  NX := -(Y2 - Y1) / Len;
  NY := (X2 - X1) / Len;
  Ph := Random * 2 * Pi;
  for I := 0 to N do
  begin
    T := I / N;
    Off := Sin(T * 9 + Ph) * 7 * T;
    W := R + Round(Sin(T * 5 + Ph) * 2);
    TileEllipse(Round(X1 + (X2 - X1) * T + NX * Off),
      Round(Y1 + (Y2 - Y1) * T + NY * Off), W, W, tWater);
  end;
end;

procedure TMainForm.MarkPath(X, Y: Integer);
var
  DX, DY: Integer;
begin
  for DY := -1 to 1 do
    for DX := -1 to 1 do
      if (X + DX >= 0) and (Y + DY >= 0) and (X + DX < SW) and (Y + DY < SH) then
        case FTiles[X + DX, Y + DY] of
          tWater: FTiles[X + DX, Y + DY] := tBridge;
          tGrass: FTiles[X + DX, Y + DY] := tPath;
        end;
end;

procedure TMainForm.TilePath(X1, Y1, X2, Y2: Integer);
var
  I, N: Integer;
begin
  N := Max(Abs(X2 - X1), Abs(Y2 - Y1));
  if N = 0 then Exit;
  for I := 0 to N do
    MarkPath(X1 + Round((X2 - X1) * I / N), Y1 + Round((Y2 - Y1) * I / N));
end;

function TMainForm.RingAt(A: Double): TPoint;
begin
  A := A - Int(A / (2 * Pi)) * 2 * Pi;
  if A < 0 then A := A + 2 * Pi;
  Result := FRing[Round(A / (2 * Pi) * High(FRing))];
end;

// distance (1..4) to the nearest shore, 5 = open water
function TMainForm.WaterDist(X, Y: Integer): Integer;
var
  R, DX, DY: Integer;
begin
  for R := 1 to 4 do
    for DY := -R to R do
      for DX := -R to R do
        if ((Abs(DX) = R) or (Abs(DY) = R)) and
           (TileAt(X + DX, Y + DY) in [tGrass, tPath, tRock, tSolid]) then
          Exit(R);
  Result := 5;
end;

procedure TMainForm.AddSprite(K: TSpriteKind; X, Y, Size: Integer);
var
  N: Integer;
begin
  N := Length(FSprites);
  SetLength(FSprites, N + 1);
  FSprites[N].Kind := K;
  FSprites[N].X := X;
  FSprites[N].Y := Y;
  FSprites[N].Size := Size;
end;

procedure TMainForm.AddLight(X, Y: Integer; Glow: Boolean);
var
  N: Integer;
begin
  N := Length(FLights);
  SetLength(FLights, N + 1);
  FLights[N].X := X;
  FLights[N].Y := Y;
  FLights[N].Glow := Glow;
end;

procedure TMainForm.BuildScene;
var
  X, Y, I, K, N, RX, RY, Edge: Integer;
  A, P: Double;
  Last, Q, E: TPoint;
  Islands: array of TPoint;
  Tmp: TSprite;
  Kind: TSpriteKind;
begin
  RandSeed := FSeed;
  SetLength(FSprites, 0);
  SetLength(FLights, 0);
  SetLength(FSparkles, 0);
  SetLength(Islands, 0);
  FillChar(FDepth, SizeOf(FDepth), 0);
  FillChar(FOcc, SizeOf(FOcc), 0);
  for X := 0 to SW - 1 do
    for Y := 0 to SH - 1 do
      FTiles[X, Y] := tGrass;

  // the lake, its bays and three rivers leaving the map
  FLakeX := 112 + Random(9) - 4;
  FLakeY := 116 + Random(9) - 4;
  TileEllipse(FLakeX, FLakeY, 60, 44, tWater);
  for I := 1 to 6 do
  begin
    A := Random * 2 * Pi;
    TileEllipse(FLakeX + Round(Cos(A) * 52), FLakeY + Round(Sin(A) * 38),
      12 + Random(10), 9 + Random(8), tWater);
  end;
  TileRiver(FLakeX + 45, FLakeY - 25, SW + 8, 20 + Random(50), 9);
  TileRiver(FLakeX - 50, FLakeY + 15, -8, 150 + Random(50), 9);
  TileRiver(FLakeX + 25, FLakeY + 38, 140 + Random(60), SH + 8, 8);

  // central island and a few small ones
  TileEllipse(FLakeX, FLakeY - 4, 30, 21, tGrass);
  for I := 1 to 400 do
  begin
    if Length(Islands) >= 4 then Break;
    X := 16 + Random(SW - 32);
    Y := 16 + Random(SH - 32);
    RX := 5 + Random(5);
    RY := 4 + Random(3);
    if BoxIs(X - RX - 7, Y - RY - 7, X + RX + 7, Y + RY + 9, [tWater]) then
    begin
      TileEllipse(X, Y, RX, RY, tGrass);
      SetLength(Islands, Length(Islands) + 1);
      Islands[High(Islands)] := Point(X, Y);
    end;
  end;

  // walking path around the lake (bridges appear where it crosses water)
  SetLength(FRing, 0);
  Last := Point(-999, -999);
  for I := 0 to 3999 do
  begin
    A := I / 4000 * 2 * Pi;
    X := FLakeX + Round(Cos(A) * (80 + Sin(A * 3 + FSeed) * 5));
    Y := FLakeY + Round(Sin(A) * (64 + Cos(A * 2 + FSeed) * 4));
    if (X <> Last.X) or (Y <> Last.Y) then
    begin
      SetLength(FRing, Length(FRing) + 1);
      FRing[High(FRing)] := Point(X, Y);
      Last := Point(X, Y);
    end;
  end;
  for I := 0 to High(FRing) do
    MarkPath(FRing[I].X, FRing[I].Y);

  // bridges to the island, plaza, exits to the map edge
  Q := RingAt(0.62 * Pi);
  TilePath(FLakeX - 8, FLakeY + 10, Q.X, Q.Y);
  Q := RingAt(1.62 * Pi);
  TilePath(FLakeX + 8, FLakeY - 16, Q.X, Q.Y);
  TileEllipse(FLakeX, FLakeY + 1, 17, 7, tPath);
  for K := 0 to 2 do
  begin
    A := K * 2 * Pi / 3 + 0.3 + Random * 0.8;
    Q := RingAt(A);
    E := Point(FLakeX + Round(Cos(A) * 220), FLakeY + Round(Sin(A) * 220));
    TilePath(Q.X, Q.Y, E.X, E.Y);
    X := Q.X + Round(Cos(A) * 11);
    Y := Q.Y + Round(Sin(A) * 11);
    if (TileAt(X, Y) = tPath) and BoxIs(X - 8, Y - 12, X + 8, Y + 1, [tGrass, tPath]) then
      AddSprite(skTorii, X, Y, 0);
  end;

  // cliffs: land edges facing south drop into the water
  for X := 0 to SW - 1 do
    for Y := 0 to SH - 2 do
      if (FTiles[X, Y] in [tGrass, tPath]) and (FTiles[X, Y + 1] = tWater) then
        for K := 1 to CLIFF_H do
        begin
          if (Y + K >= SH) or (FTiles[X, Y + K] <> tWater) then Break;
          FTiles[X, Y + K] := tRock;
          FDepth[X, Y + K] := K;
        end;

  // tea house next to the path
  for I := 1 to 600 do
  begin
    X := 16 + Random(SW - 32);
    Y := 22 + Random(SH - 28);
    if BoxIs(X - 12, Y - 14, X + 12, Y + 1, [tGrass]) and
       not BoxIs(X - 12, Y + 2, X + 12, Y + 6, [tGrass]) then
    begin
      for RY := Y - 14 to Y + 1 do
        for RX := X - 12 to X + 12 do
          FTiles[RX, RY] := tSolid;
      AddSprite(skTeaHouse, X, Y, 0);
      Break;
    end;
  end;

  // lamp posts along the ring path
  I := 20;
  while I < Length(FRing) do
  begin
    A := ArcTan2(FRing[I].Y - FLakeY, FRing[I].X - FLakeX);
    X := FRing[I].X + Round(Cos(A) * 3);
    Y := FRing[I].Y + Round(Sin(A) * 3);
    if BoxIs(X - 1, Y - 6, X + 1, Y, [tGrass]) then
    begin
      for RY := Y - 6 to Y do
        for RX := X - 1 to X + 1 do
          FTiles[RX, RY] := tSolid;
      AddSprite(skLamp, X, Y, 0);
    end;
    Inc(I, 75);
  end;

  // the pagoda, its lanterns and two cherry trees on the island
  AddSprite(skPagoda, FLakeX, FLakeY + 4, 0);
  AddSprite(skStoneLantern, FLakeX - 15, FLakeY + 7, 0);
  AddSprite(skStoneLantern, FLakeX + 15, FLakeY + 7, 0);
  AddSprite(skSakura, FLakeX - 23, FLakeY - 1, 5);
  AddSprite(skSakura, FLakeX + 23, FLakeY - 5, 4);
  for I := 0 to High(Islands) do
  begin
    if Random(2) = 0 then Kind := skSakura else Kind := skRound;
    AddSprite(Kind, Islands[I].X, Islands[I].Y + 1, 3 + Random(2));
  end;

  // trees: a dense forest at the border, scattered inside
  for I := 1 to 6000 do
  begin
    X := Random(SW);
    Y := 3 + Random(SH - 3);
    if FOcc[X, Y] or not BoxIs(X - 2, Y - 1, X + 2, Y, [tGrass]) then Continue;
    if (Abs(X - FLakeX) < 24) and (Y > FLakeY - 64) and (Y < FLakeY + 12) then Continue;
    Edge := Min(Min(X, SW - 1 - X), Min(Y, SH - 1 - Y));
    if Edge < 26 then P := 0.9 else P := 0.1;
    if Random >= P then Continue;
    if not BoxIs(X - 9, Y - 9, X + 9, Y + 9, [tGrass, tPath, tSolid]) then
      P := 0.45                          // near the water
    else
      P := 0.07;
    if Random < P then Kind := skSakura
    else if (Edge < 26) and (Random < 0.55) then Kind := skPine
    else Kind := skRound;
    AddSprite(Kind, X, Y, 3 + Random(3));
    for RY := Max(0, Y - 4) to Min(SH - 1, Y + 3) do
      for RX := Max(0, X - 4) to Min(SW - 1, X + 4) do
        FOcc[RX, RY] := True;
  end;

  // painter's order: back to front
  for I := 1 to High(FSprites) do
  begin
    Tmp := FSprites[I];
    N := I - 1;
    while (N >= 0) and (FSprites[N].Y > Tmp.Y) do
    begin
      FSprites[N + 1] := FSprites[N];
      Dec(N);
    end;
    FSprites[N + 1] := Tmp;
  end;

  // spots where the water glitters
  for I := 1 to 3000 do
  begin
    if Length(FSparkles) >= 420 then Break;
    X := Random(SW - 2);
    Y := Random(SH);
    if (FTiles[X, Y] = tWater) and (FTiles[X + 1, Y] = tWater) then
    begin
      SetLength(FSparkles, Length(FSparkles) + 1);
      FSparkles[High(FSparkles)].X := X;
      FSparkles[High(FSparkles)].Y := Y;
      FSparkles[High(FSparkles)].Phase := Random * 2 * Pi;
      FSparkles[High(FSparkles)].Speed := 0.03 + Random * 0.05;
    end;
  end;

  PaintTiles;
  for I := 0 to High(FSprites) do
    DrawShadow(FSprites[I]);
  for I := 0 to High(FSprites) do
    DrawSprite(FSprites[I]);
end;

procedure TMainForm.PaintTiles;
var
  X, Y, D: Integer;
  H: LongWord;
  V: Double;
  C: TBGRAPixel;
begin
  for Y := 0 to SH - 1 do
    for X := 0 to SW - 1 do
    begin
      H := Hash(X, Y, FSeed);
      case FTiles[X, Y] of
        tGrass, tSolid:
          begin
            V := Sin(X * 0.11 + FSeed) + Sin(Y * 0.13) * 0.8 +
              Sin((X + Y) * 0.05) * 0.7 + (H mod 100) / 100 * 0.6;
            if V > 1.3 then C := RGBc($5AAB62)
            else if V < -1.0 then C := RGBc($458A4F)
            else C := RGBc($4E9A58);
            if TileAt(X, Y + 1) = tRock then C := RGBc($3A7A46)
            else if H mod 420 = 0 then C := RGBc($F7D9E6)
            else if H mod 530 = 0 then C := RGBc($FFF3B0);
          end;
        tWater:
          begin
            D := WaterDist(X, Y);
            if TileAt(X, Y - 1) = tBridge then C := RGBc($26878A)
            else if D = 1 then C := RGBc($A6EBDD)
            else if D = 2 then C := RGBc($63D0C4)
            else if (D <= 4) or (H mod 3 = 0) then C := RGBc($46C0B8)
            else if Sin(X * 0.07 + Y * 0.05 + FSeed) > 0.6 then C := RGBc($34ACAA)
            else C := RGBc($3DB8B3);
          end;
        tPath:
          begin
            if (TileAt(X - 1, Y) in [tGrass, tSolid, tRock]) or
               (TileAt(X + 1, Y) in [tGrass, tSolid, tRock]) or
               (TileAt(X, Y - 1) in [tGrass, tSolid, tRock]) or
               (TileAt(X, Y + 1) in [tGrass, tSolid, tRock]) then
              C := RGBc($A9917F)
            else if H mod 23 = 0 then C := RGBc($BFA898)
            else C := RGBc($D2BDAA);
          end;
        tBridge:
          begin
            if (TileAt(X - 1, Y) = tWater) or (TileAt(X + 1, Y) = tWater) or
               (TileAt(X, Y - 1) in [tWater, tRock]) or (TileAt(X, Y + 1) = tWater) then
            begin
              if (X + Y) mod 4 = 0 then C := RGBc($E2694F) else C := RGBc($7A2320);
            end
            else if (X + Y) mod 3 = 0 then C := RGBc($A83A28)
            else C := RGBc($C0452F);
          end;
        tRock:
          begin
            D := FDepth[X, Y];
            if TileAt(X, Y + 1) <> tRock then C := RGBc($56425A)
            else if D = 1 then C := RGBc($A0809A)
            else if D mod 3 = 0 then C := RGBc($6E5470)
            else if H mod 7 = 0 then C := RGBc($B596AE)
            else C := RGBc($8A6B85);
          end;
      end;
      FStatic.SetPixel(X, Y, C);
    end;
end;

procedure TMainForm.DrawShadow(const S: TSprite);
begin
  case S.Kind of
    skRound, skSakura: ShadowEllipse(FStatic, S.X + 2, S.Y, S.Size + 2, S.Size div 2 + 1);
    skPine: ShadowEllipse(FStatic, S.X + 2, S.Y, S.Size + 1, 2);
    skPagoda: ShadowEllipse(FStatic, S.X + 6, S.Y + 1, 22, 5);
    skTeaHouse: ShadowEllipse(FStatic, S.X + 3, S.Y + 1, 13, 3);
    skTorii: ShadowEllipse(FStatic, S.X + 2, S.Y, 6, 1);
  end;
end;

procedure TMainForm.DrawSprite(const S: TSprite);
var
  B: TBGRABitmap;
  X, Y, Sz, I, R, W, BY, CY, YB, BW, RW, XX: Integer;
  Dark, Mid, Light, Trunk, Red, Gold, Roof, RoofD, RoofL: TBGRAPixel;
begin
  B := FStatic;
  X := S.X;
  Y := S.Y;
  Sz := S.Size;
  case S.Kind of
    skRound, skSakura:
      begin
        if S.Kind = skSakura then
        begin
          Dark := RGBc($D9789F); Mid := RGBc($F2A2C0); Light := RGBc($FBD3E3);
          Trunk := RGBc($5B3A33);
        end
        else
        begin
          Dark := RGBc($2E6B43); Mid := RGBc($3F8A4F); Light := RGBc($63B061);
          Trunk := RGBc($6B4A32);
        end;
        Box(B, X, Y - 2, X, Y, Trunk);
        CY := Y - 2 - Sz;
        Disc(B, X, CY, Sz, Dark);
        if S.Kind = skSakura then
        begin
          Disc(B, X - Sz div 2 - 1, CY + 1, Sz - 1, Dark);
          Disc(B, X + Sz div 2 + 1, CY + 1, Sz - 1, Dark);
        end;
        Disc(B, X - 1, CY - 1, Sz - 1, Mid);
        Disc(B, X - 2, CY - 2, Sz * 0.45, Light);
        for I := 0 to Sz * 4 do
          PutPx(B, X - Sz + Random(2 * Sz + 1), CY - Sz + 1 + Random(2 * Sz), Dark);
        for I := 0 to Sz do
          PutPx(B, X - Sz + 1 + Random(Sz), CY - Sz + 1 + Random(Sz), Light);
      end;
    skPine:
      begin
        Dark := RGBc($1F5139); Mid := RGBc($2C6B48); Light := RGBc($3F8457);
        Box(B, X, Y - 1, X, Y, RGBc($5A3E2A));
        for I := 0 to 2 do
        begin
          BY := Y - 2 - I * Sz;
          for R := 0 to Sz + 2 do
          begin
            W := Round((Sz + 1 - I) * R / (Sz + 2));
            HLine(B, X - W, X + W, BY - Sz - 2 + R, Dark);
            if W > 1 then HLine(B, X - W + 1, X - 1, BY - Sz - 2 + R, Mid);
            if W > 0 then PutPx(B, X - W, BY - Sz - 2 + R, Light);
          end;
        end;
      end;
    skTorii:
      begin
        Red := RGBc($D63F2E);
        Dark := RGBc($2A2028);
        Box(B, X - 4, Y - 9, X - 4, Y, Red);
        Box(B, X + 4, Y - 9, X + 4, Y, Red);
        PutPx(B, X - 4, Y, Dark);
        PutPx(B, X + 4, Y, Dark);
        HLine(B, X - 6, X + 6, Y - 7, Red);
        Box(B, X, Y - 10, X, Y - 8, Red);
        HLine(B, X - 6, X + 6, Y - 10, Red);
        HLine(B, X - 7, X + 7, Y - 11, Dark);
        PutPx(B, X - 8, Y - 12, Dark);
        PutPx(B, X + 8, Y - 12, Dark);
      end;
    skLamp:
      begin
        Box(B, X, Y - 4, X, Y, RGBc($3B3040));
        PutPx(B, X, Y - 5, RGBc($F7E7B5));
        HLine(B, X - 1, X + 1, Y - 6, RGBc($3B3040));
        AddLight(X, Y - 5, True);
      end;
    skStoneLantern:
      begin
        Gold := RGBc($A39AA6);
        Dark := RGBc($6F6878);
        Box(B, X - 1, Y - 1, X + 1, Y, Dark);
        Box(B, X, Y - 3, X, Y - 2, Gold);
        Box(B, X - 1, Y - 5, X + 1, Y - 4, Gold);
        PutPx(B, X, Y - 4, RGBc($4A4450));
        HLine(B, X - 2, X + 2, Y - 6, Dark);
        PutPx(B, X, Y - 7, Gold);
        AddLight(X, Y - 4, True);
      end;
    skPagoda:
      begin
        Red := RGBc($C8463A);
        Gold := RGBc($E3B948);
        Roof := RGBc($2F7D5E);
        RoofD := RGBc($1E4A3D);
        RoofL := RGBc($52A77D);
        // stone platform with stairs
        Box(B, X - 18, Y - 2, X + 18, Y + 2, RGBc($7E7484));
        HLine(B, X - 18, X + 18, Y - 2, RGBc($B5ABB8));
        Box(B, X - 14, Y - 5, X + 14, Y - 3, RGBc($9A90A0));
        HLine(B, X - 14, X + 14, Y - 5, RGBc($B5ABB8));
        Box(B, X - 3, Y - 2, X + 3, Y + 3, RGBc($C9BFC9));
        HLine(B, X - 3, X + 3, Y, RGBc($8A808E));
        HLine(B, X - 3, X + 3, Y + 2, RGBc($8A808E));
        YB := Y - 6;
        for I := 0 to 3 do
        begin
          BW := 9 - I * 2;
          Box(B, X - BW, YB - 5, X + BW, YB, Red);
          Box(B, X - BW, YB - 5, X - BW, YB, RGBc($9C3029));
          Box(B, X + BW, YB - 5, X + BW, YB, RGBc($9C3029));
          HLine(B, X - BW, X + BW, YB - 5, Gold);
          HLine(B, X - BW - 1, X + BW + 1, YB, RGBc($8E2F28));
          XX := X - BW + 2;
          while XX <= X + BW - 2 do
          begin
            PutPx(B, XX, YB - 3, RGBc($4A1C20));
            PutPx(B, XX, YB - 2, RGBc($4A1C20));
            AddLight(XX, YB - 3, False);
            AddLight(XX, YB - 2, False);
            Inc(XX, 3);
          end;
          RW := BW + 5;
          HLine(B, X - RW, X + RW, YB - 6, RoofD);
          HLine(B, X - RW + 1, X + RW - 1, YB - 7, Roof);
          HLine(B, X - RW + 3, X + RW - 3, YB - 8, RoofL);
          HLine(B, X - RW + 5, X + RW - 5, YB - 9, Roof);
          PutPx(B, X - RW - 1, YB - 7, Roof);
          PutPx(B, X + RW + 1, YB - 7, Roof);
          PutPx(B, X - RW - 1, YB - 8, RoofL);
          PutPx(B, X + RW + 1, YB - 8, RoofL);
          PutPx(B, X - RW, YB - 5, Gold);
          PutPx(B, X + RW, YB - 5, Gold);
          Dec(YB, 10);
        end;
        Box(B, X, YB - 8, X, YB + 1, Gold);
        HLine(B, X - 1, X + 1, YB - 2, Gold);
        HLine(B, X - 1, X + 1, YB - 4, Gold);
        HLine(B, X - 1, X + 1, YB - 6, Gold);
        PutPx(B, X, YB - 9, RGBc($FFF0A0));
      end;
    skTeaHouse:
      begin
        Roof := RGBc($2F7D5E);
        RoofD := RGBc($1E4A3D);
        RoofL := RGBc($52A77D);
        HLine(B, X - 10, X + 10, Y + 1, RGBc($9A90A0));
        Box(B, X - 8, Y - 6, X + 8, Y, RGBc($EADFC8));
        for XX in [X - 8, X - 3, X + 3, X + 8] do
          Box(B, XX, Y - 6, XX, Y, RGBc($B23A2E));
        Box(B, X - 1, Y - 4, X + 1, Y, RGBc($4A3530));
        Box(B, X - 6, Y - 4, X - 5, Y - 3, RGBc($6B5040));
        Box(B, X + 5, Y - 4, X + 6, Y - 3, RGBc($6B5040));
        AddLight(X - 6, Y - 4, False);
        AddLight(X + 6, Y - 4, False);
        AddLight(X - 5, Y - 3, False);
        AddLight(X + 5, Y - 3, False);
        for R := 0 to 5 do
        begin
          W := 11 - R;
          if R = 0 then HLine(B, X - W, X + W, Y - 7, RoofD)
          else if R = 4 then HLine(B, X - W, X + W, Y - 7 - R, RoofL)
          else HLine(B, X - W, X + W, Y - 7 - R, Roof);
        end;
        HLine(B, X - 5, X + 5, Y - 13, RoofD);
        PutPx(B, X - 12, Y - 8, Roof);
        PutPx(B, X + 12, Y - 8, Roof);
      end;
  end;
end;

{ ---- life ---- }

function TMainForm.CanBoat(X, Y: Double): Boolean;
var
  IX, IY: Integer;
begin
  IX := Round(X);
  IY := Round(Y);
  Result := BoxIs(IX - 5, IY - 2, IX + 5, IY + 1, [tWater]);
end;

procedure TMainForm.AddBoat(X, Y: Double);
var
  N: Integer;
begin
  N := Length(FBoats);
  SetLength(FBoats, N + 1);
  FBoats[N].X := X;
  FBoats[N].Y := Y;
  FBoats[N].Dir := Random * 2 * Pi;
  FBoats[N].Speed := 0.12 + Random * 0.12;
  if Random(4) = 0 then FBoats[N].Kind := 1 else FBoats[N].Kind := 0;
end;

procedure TMainForm.AddBoatRandom;
var
  I, X, Y: Integer;
begin
  for I := 1 to 2000 do
  begin
    X := Random(SW);
    Y := Random(SH);
    if CanBoat(X, Y) then
    begin
      AddBoat(X, Y);
      Exit;
    end;
  end;
end;

procedure TMainForm.NewCloud(var C: TCloud; X: Double);
var
  J, M: Integer;
begin
  C.X := X;
  C.Y := 12 + Random(SH - 60);
  C.Speed := 0.05 + Random * 0.07;
  for J := 0 to 5 do
  begin
    M := Abs(J * 2 - 5) div 2;           // 2,1,0,0,1,2
    C.DX[J] := J * 7 - 18 + Random(4);
    C.DY[J] := 2 * M + Random(3) - 2;
    C.R[J] := 4 + Random(3) + 2 - M;
  end;
end;

procedure TMainForm.InitLife;
var
  I: Integer;
begin
  SetLength(FBoats, 0);
  for I := 1 to 6 do
    AddBoatRandom;
  SetLength(FWalkers, MAX_WALKERS);
  for I := 0 to MAX_WALKERS - 1 do
  begin
    FWalkers[I].Pos := Random * Length(FRing);
    FWalkers[I].Speed := (0.12 + Random * 0.2) * (2 * Random(2) - 1);
    FWalkers[I].Lane := Random(3) - 1;
    FWalkers[I].Pause := 0;
    FWalkers[I].Shirt := ShirtColor(Random(7));
    FWalkers[I].Parasol := Random(6) = 0;
  end;
  SetLength(FPetals, 0);
  SetLength(FClouds, 3);
  for I := 0 to High(FClouds) do
    NewCloud(FClouds[I], Random(SW + 80) - 40);
  SetLength(FBirds, 3);
  for I := 0 to High(FBirds) do
  begin
    FBirds[I].X := Random(SW);
    FBirds[I].Y := 10 + Random(SH div 2);
    FBirds[I].VX := 0.3 + Random * 0.3;
  end;
end;

function TMainForm.Hour: Double;
begin
  case FMode of
    0: Result := 12;
    1: Result := 18.4;
    2: Result := 23;
  else
    Result := FClock;
  end;
end;

function TMainForm.ActiveWalkers: Integer;
begin
  if not FShow[3] then Exit(0);
  Result := Min(MAX_WALKERS, Round(FVisitorTarget * Crowd(Hour)));
end;

procedure TMainForm.Step;
var
  I, N, Sak: Integer;
  B: ^TBoat;
  NX, NY: Double;
begin
  Inc(FTick);
  FClock := FClock + 1 / 120;           // one park minute every 2 frames
  if FClock >= 24 then FClock := FClock - 24;

  for I := 0 to High(FBoats) do
  begin
    B := @FBoats[I];
    B^.Dir := B^.Dir + (Random - 0.5) * 0.04;
    NX := B^.X + Cos(B^.Dir) * B^.Speed;
    NY := B^.Y + Sin(B^.Dir) * B^.Speed * 0.7;
    if CanBoat(NX, NY) then
    begin
      B^.X := NX;
      B^.Y := NY;
    end
    else
      B^.Dir := B^.Dir + Pi * (0.5 + Random);
  end;

  N := Length(FRing);
  for I := 0 to ActiveWalkers - 1 do
    with FWalkers[I] do
      if Pause > 0 then Dec(Pause)
      else
      begin
        Pos := Pos + Speed;
        if Pos >= N then Pos := Pos - N;
        if Pos < 0 then Pos := Pos + N;
        if Random(500) = 0 then Pause := 30 + Random(90);
      end;

  // petals fall from the cherry trees
  if FShow[0] then
  begin
    Sak := 0;
    for I := 0 to High(FSprites) do
      if FSprites[I].Kind = skSakura then Inc(Sak);
    if (Sak > 0) and (Length(FPetals) < MAX_PETALS) then
      for N := 1 to 2 do
      begin
        repeat
          I := Random(Length(FSprites));
        until FSprites[I].Kind = skSakura;
        SetLength(FPetals, Length(FPetals) + 1);
        with FPetals[High(FPetals)] do
        begin
          X := FSprites[I].X + Random(2 * FSprites[I].Size + 1) - FSprites[I].Size;
          Y := FSprites[I].Y - 2 - FSprites[I].Size - Random(FSprites[I].Size + 1);
          VX := 0.12 + Random * 0.2;
          VY := 0.06 + Random * 0.1;
          Life := 140 + Random(140);
          Light := Random(2) = 0;
        end;
      end;
  end;
  N := 0;
  for I := 0 to High(FPetals) do
  begin
    with FPetals[I] do
    begin
      X := X + VX + Sin((FTick + I * 7) * 0.08) * 0.12;
      Y := Y + VY;
      Dec(Life);
    end;
    if (FPetals[I].Life > 0) and (FPetals[I].X < SW) and (FPetals[I].Y < SH) then
    begin
      FPetals[N] := FPetals[I];
      Inc(N);
    end;
  end;
  SetLength(FPetals, N);

  for I := 0 to High(FClouds) do
  begin
    FClouds[I].X := FClouds[I].X + FClouds[I].Speed;
    if FClouds[I].X > SW + 40 then NewCloud(FClouds[I], -40);
  end;
  for I := 0 to High(FBirds) do
  begin
    FBirds[I].X := FBirds[I].X + FBirds[I].VX;
    FBirds[I].Y := FBirds[I].Y + Sin((FTick + I * 40) * 0.05) * 0.1;
    if FBirds[I].X > SW + 4 then
    begin
      FBirds[I].X := -4;
      FBirds[I].Y := 10 + Random(SH div 2);
    end;
  end;
end;

{ ---- rendering ---- }

procedure TMainForm.RenderScene;
var
  F: TBGRABitmap;
  I, J, R, C, X, Y, Dir, N, CX, CY, DX, DY, Lane: Integer;
  V, Night, Dusk, K: Double;
  Art: string[9];
  P, P2: TPoint;
begin
  F := FFrame;
  F.PutImage(0, 0, FStatic, dmSet);

  if FShow[2] then
    for I := 0 to High(FSparkles) do
    begin
      V := Sin(FTick * FSparkles[I].Speed + FSparkles[I].Phase);
      if V > 0.82 then
      begin
        PutPx(F, FSparkles[I].X, FSparkles[I].Y, RGBc($D8FFF6));
        PutPx(F, FSparkles[I].X + 1, FSparkles[I].Y, RGBc($B8F5EA));
      end;
    end;

  // boats with a small wake
  for I := 0 to High(FBoats) do
  begin
    X := Round(FBoats[I].X);
    Y := Round(FBoats[I].Y);
    if Cos(FBoats[I].Dir) >= 0 then Dir := 1 else Dir := -1;
    J := (FTick div 6 + I) mod 3;
    BlendPx(F, X - Dir * 5, Y, BGRA(220, 250, 245, 200));
    BlendPx(F, X - Dir * (6 + J), Y - 1, BGRA(220, 250, 245, 140));
    BlendPx(F, X - Dir * (6 + J), Y + 1, BGRA(220, 250, 245, 140));
    for R := 0 to 6 do
    begin
      if FBoats[I].Kind = 0 then Art := SWAN[R] else Art := ROWBOAT[R];
      for C := 1 to 9 do
        if Art[C] <> '.' then
        begin
          if Dir > 0 then J := C - 1 else J := 9 - C;
          PutPx(F, X - 4 + J, Y - 5 + R, ArtColor(Art[C]));
        end;
    end;
  end;

  // visitors on the ring path
  N := Length(FRing);
  for I := 0 to ActiveWalkers - 1 do
  begin
    J := Trunc(FWalkers[I].Pos) mod N;
    P := FRing[J];
    P2 := FRing[(J + 3) mod N];
    Lane := FWalkers[I].Lane;
    if Abs(P2.X - P.X) > Abs(P2.Y - P.Y) then Inc(P.Y, Lane) else Inc(P.X, Lane);
    PutPx(F, P.X, P.Y - 2, RGBc($F2C9A0));
    PutPx(F, P.X, P.Y - 1, FWalkers[I].Shirt);
    if (FWalkers[I].Pause > 0) or ((FTick div 8 + I) mod 2 = 0) then
      PutPx(F, P.X, P.Y, RGBc($3A3045));
    if FWalkers[I].Parasol then
      HLine(F, P.X - 1, P.X + 1, P.Y - 3, RGBc($F7B6CF));
  end;

  if FShow[0] then
    for I := 0 to High(FPetals) do
      if FPetals[I].Light then
        PutPx(F, Round(FPetals[I].X), Round(FPetals[I].Y), RGBc($FFD6E6))
      else
        PutPx(F, Round(FPetals[I].X), Round(FPetals[I].Y), RGBc($F08DB4));

  if FShow[1] then
  begin
    for I := 0 to High(FClouds) do
      for DY := -5 to 5 do
        for DX := -24 to 24 do
          if Sqr(DX / 24) + Sqr(DY / 5) <= 1 then
            BlendPx(F, Round(FClouds[I].X) + 10 + DX, Round(FClouds[I].Y) + 34 + DY,
              BGRA(20, 30, 60, 28));
    for I := 0 to High(FBirds) do
    begin
      X := Round(FBirds[I].X);
      Y := Round(FBirds[I].Y);
      PutPx(F, X, Y, RGBc($3A3045));
      if (FTick div 8 + I) mod 2 = 0 then
      begin
        PutPx(F, X - 1, Y - 1, RGBc($3A3045));
        PutPx(F, X + 1, Y - 1, RGBc($3A3045));
      end
      else
      begin
        PutPx(F, X - 1, Y, RGBc($3A3045));
        PutPx(F, X + 1, Y, RGBc($3A3045));
      end;
    end;
    for I := 0 to High(FClouds) do
      for J := 0 to 1 do                // lavender underside, then white top
        for C := 0 to 5 do
        begin
          CX := Round(FClouds[I].X) + FClouds[I].DX[C];
          CY := Round(FClouds[I].Y) + FClouds[I].DY[C] - J * 2;
          R := FClouds[I].R[C] - J;
          for DY := -R to R do
            for DX := -R to R do
              if DX * DX + DY * DY <= R * R + R then
                if J = 0 then PutPx(F, CX + DX, CY + DY, RGBc($D6D0EC))
                else PutPx(F, CX + DX, CY + DY, RGBc($FFFFFF));
        end;
  end;

  // time of day
  TimeLight(Hour, Night, Dusk);
  if Dusk > 0 then
    F.FillRect(0, 0, SW, SH, BGRA(255, 110, 70, Round(Dusk * 70)), dmDrawWithTransparency);
  if Night > 0 then
    F.FillRect(0, 0, SW, SH, BGRA(12, 20, 70, Round(Night * 150)), dmDrawWithTransparency);
  if Night > 0.3 then
  begin
    K := Min(1, (Night - 0.3) / 0.4);
    for I := 0 to High(FLights) do
      with FLights[I] do
        if Glow then
        begin
          Disc(F, X, Y, 4, BGRA(255, 190, 90, Round(40 * K)), True);
          Disc(F, X, Y, 1.6, BGRA(255, 210, 120, Round(80 * K)), True);
          BlendPx(F, X, Y, BGRA(255, 236, 170, Round(255 * K)));
        end
        else
          BlendPx(F, X, Y, BGRA(255, 214, 120, Round(255 * K)));
  end;
end;

procedure TMainForm.SetFont(Size: Integer; Bold: Boolean);
begin
  FBack.FontName := 'Segoe UI';
  FBack.FontHeight := Size;
  if Bold then FBack.FontStyle := [fsBold] else FBack.FontStyle := [];
  FBack.FontQuality := fqFineAntialiasing;
end;

procedure TMainForm.AddItem(X1, Y1, X2, Y2, Id: Integer);
var
  N: Integer;
begin
  N := Length(FItems);
  SetLength(FItems, N + 1);
  FItems[N].R := Rect(X1, Y1, X2, Y2);
  FItems[N].Id := Id;
end;

function TMainForm.ItemAt(X, Y: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FItems) do
    if (X >= FItems[I].R.Left) and (X < FItems[I].R.Right) and
       (Y >= FItems[I].R.Top) and (Y < FItems[I].R.Bottom) then
      Exit(FItems[I].Id);
  Result := 0;
end;

procedure TMainForm.RenderPanel;
var
  B: TBGRABitmap;
  X0, X1, X2, Y, I, SegW, BarW, BX, BH, CurH: Integer;
  H, Mx: Double;
  S: string;
  Pink, Teal, Card, Border, Txt, Dim, Bg, Fill: TBGRAPixel;

  procedure CardBox(Y1, Y2: Integer; const Title, Right: string);
  begin
    B.FillRoundRectAntialias(X1, Y1, X2, Y2, 12, 12, Card);
    B.RoundRectAntialias(X1, Y1, X2, Y2, 12, 12, Border, 1);
    SetFont(12, True);
    B.TextOut(X1 + 14, Y1 + 10, UpperCase(Title), Dim);
    if Right <> '' then
    begin
      SetFont(14, True);
      B.TextOut(X2 - 14 - B.TextSize(Right).cx, Y1 + 8, Right, Pink);
    end;
  end;

  procedure CenterText(L, T, R, Bt: Integer; const Str: string; C: TBGRAPixel);
  var
    Sz: TSize;
  begin
    Sz := B.TextSize(Str);
    B.TextOut((L + R - Sz.cx) div 2, (T + Bt - Sz.cy) div 2, Str, C);
  end;

  procedure Switch(Y1, Idx: Integer);
  var
    Hot: Boolean;
    SX: Integer;
  begin
    Hot := FHover = ID_TOGGLE + Idx;
    SetFont(15, False);
    if Hot then B.TextOut(X1 + 16, Y1 + 2, TOGGLE_NAMES[Idx], RGBc($FFFFFF))
    else B.TextOut(X1 + 16, Y1 + 2, TOGGLE_NAMES[Idx], Txt);
    SX := X2 - 58;
    if FShow[Idx] then
    begin
      B.FillRoundRectAntialias(SX, Y1 + 3, SX + 40, Y1 + 23, 10, 10, Teal);
      B.FillEllipseAntialias(SX + 30, Y1 + 13, 7, 7, RGBc($FFFFFF));
    end
    else
    begin
      B.FillRoundRectAntialias(SX, Y1 + 3, SX + 40, Y1 + 23, 10, 10, RGBc($4A3A58));
      B.FillEllipseAntialias(SX + 10, Y1 + 13, 7, 7, RGBc($B9A6C2));
    end;
    AddItem(X1 + 6, Y1, X2 - 6, Y1 + 26, ID_TOGGLE + Idx);
  end;

  procedure SmallButton(L, T: Integer; const Str: string; Id: Integer);
  begin
    if FHover = Id then Fill := RGBc($5A4870) else Fill := RGBc($443453);
    B.FillRoundRectAntialias(L, T, L + 30, T + 28, 8, 8, Fill);
    SetFont(18, True);
    CenterText(L, T - 1, L + 30, T + 28, Str, Txt);
    AddItem(L, T, L + 30, T + 28, Id);
  end;

  procedure Stepper(Y1: Integer; const Name: string; Value, DecId, IncId: Integer);
  begin
    SetFont(15, False);
    B.TextOut(X1 + 16, Y1 + 4, Name, Txt);
    SmallButton(X2 - 116, Y1, '-', DecId);
    SetFont(16, True);
    CenterText(X2 - 86, Y1, X2 - 46, Y1 + 28, IntToStr(Value), RGBc($FFFFFF));
    SmallButton(X2 - 46, Y1, '+', IncId);
  end;

  procedure BigButton(L, T, R, Bt: Integer; const Str: string; Id: Integer; Primary: Boolean);
  begin
    if Primary then
    begin
      if FHover = Id then Fill := RGBc($F7B6CF) else Fill := Pink;
      B.FillRoundRectAntialias(L, T, R, Bt, 10, 10, Fill);
      SetFont(15, True);
      CenterText(L, T, R, Bt, Str, RGBc($2A1E35));
    end
    else
    begin
      if FHover = Id then B.FillRoundRectAntialias(L, T, R, Bt, 10, 10, RGBc($2F4F55));
      B.RoundRectAntialias(L, T, R, Bt, 10, 10, Teal, 1.5);
      SetFont(15, True);
      CenterText(L, T, R, Bt, Str, Teal);
    end;
    AddItem(L, T, R, Bt, Id);
  end;

begin
  B := FBack;
  SetLength(FItems, 0);
  Pink := RGBc($F29BBF);
  Teal := RGBc($4FC9BD);
  Card := RGBc($33263F);
  Border := RGBc($4A3A58);
  Txt := RGBc($F4E9F0);
  Dim := RGBc($B9A6C2);
  Bg := RGBc($241A2E);
  X0 := SW * PX;
  X1 := X0 + 16;
  X2 := X0 + PANEL_W - 16;

  B.GradientFill(X0, 0, X0 + PANEL_W, SH * PX, RGBc($2A1E35), RGBc($181220),
    gtLinear, PointF(X0, 0), PointF(X0, SH * PX), dmSet);
  B.FillRect(X0, 0, X0 + 2, SH * PX, RGBc($F29BBF, 120), dmDrawWithTransparency);

  // header: a sakura blossom and the title
  for I := 0 to 4 do
  begin
    H := I * 2 * Pi / 5 - Pi / 2;
    B.FillEllipseAntialias(X1 + 16 + Cos(H) * 8, 34 + Sin(H) * 8, 6, 6, Pink);
  end;
  B.FillEllipseAntialias(X1 + 16, 34, 3.5, 3.5, RGBc($FFE08A));
  SetFont(24, True);
  B.TextOut(X1 + 42, 14, 'Sakura Lake Park', Txt);
  SetFont(13, False);
  B.TextOut(X1 + 43, 44, 'BGRABitmap park control', Dim);

  // time of day
  H := Hour;
  Y := 76;
  CardBox(Y, Y + 84, 'Time of day',
    Format('%.2d:%.2d', [Trunc(H), Trunc(Frac(H) * 60)]));
  SegW := (X2 - X1 - 28) div 4;
  B.FillRoundRectAntialias(X1 + 14, Y + 38, X1 + 14 + SegW * 4, Y + 70, 10, 10, Bg);
  for I := 0 to 3 do
  begin
    BX := X1 + 14 + I * SegW;
    if FMode = I then
      B.FillRoundRectAntialias(BX + 2, Y + 40, BX + SegW - 2, Y + 68, 8, 8, Pink)
    else if FHover = ID_MODE + I then
      B.FillRoundRectAntialias(BX + 2, Y + 40, BX + SegW - 2, Y + 68, 8, 8, RGBc($443453));
    SetFont(14, True);
    if FMode = I then CenterText(BX, Y + 38, BX + SegW, Y + 70, MODE_NAMES[I], RGBc($2A1E35))
    else CenterText(BX, Y + 38, BX + SegW, Y + 70, MODE_NAMES[I], Txt);
    AddItem(BX, Y + 38, BX + SegW, Y + 70, ID_MODE + I);
  end;

  // scene switches
  Y := 170;
  CardBox(Y, Y + 150, 'Scene', '');
  for I := 0 to 3 do
    Switch(Y + 34 + I * 28, I);

  // lake and paths
  Y := 330;
  CardBox(Y, Y + 108, 'Lake & paths', '');
  Stepper(Y + 34, 'Swan boats', Length(FBoats), ID_BOAT_DEC, ID_BOAT_INC);
  Stepper(Y + 68, 'Visitors (peak)', FVisitorTarget, ID_VIS_DEC, ID_VIS_INC);

  // visitors by hour
  Y := 448;
  CardBox(Y, Y + 120, 'Visitors today', Format('%d now', [ActiveWalkers]));
  BarW := (X2 - X1 - 28) div 24;
  BX := X1 + 14 + (X2 - X1 - 28 - BarW * 24) div 2;
  Mx := Max(1, FVisitorTarget);
  CurH := Trunc(H);
  for I := 0 to 23 do
  begin
    BH := Max(2, Round(Crowd(I + 0.5) * FVisitorTarget / Mx * 62));
    if I = CurH then Fill := Pink
    else if FShow[3] then Fill := RGBc($4FC9BD, 170)
    else Fill := RGBc($4A3A58);
    B.FillRoundRectAntialias(BX + I * BarW + 1, Y + 100 - BH, BX + (I + 1) * BarW - 2,
      Y + 100, 2, 2, Fill);
  end;
  SetFont(11, False);
  for I := 0 to 3 do
  begin
    S := Format('%.2d', [I * 6]);
    B.TextOut(BX + I * 6 * BarW, Y + 102, S, Dim);
  end;

  // actions
  Y := 580;
  BigButton(X1, Y, (X1 + X2) div 2 - 5, Y + 36, 'New park', ID_NEW, True);
  BigButton((X1 + X2) div 2 + 5, Y, X2, Y + 36, 'Save PNG', ID_SAVE, False);

  SetFont(12, False);
  if FTick < FToastUntil then S := FToast
  else S := 'Click the lake to launch a boat';
  B.TextOut(X1 + 2, 630, S, Dim);
  S := Format('seed %d  ·  %.0f fps', [FSeed, FFps]);
  B.TextOut(X2 - B.TextSize(S).cx, 650, S, RGBc($7E6C8A));
end;

procedure TMainForm.RenderAll;
var
  Big: TBGRACustomBitmap;
begin
  RenderScene;
  Big := FFrame.Resample(SW * PX, SH * PX, rmSimpleStretch);
  try
    FBack.PutImage(0, 0, Big, dmSet);
  finally
    Big.Free;
  end;
  RenderPanel;
end;

procedure TMainForm.ShowToast(const S: string);
begin
  FToast := S;
  FToastUntil := FTick + 90;
end;

procedure TMainForm.HandleItem(Id: Integer);
var
  Part: TBGRACustomBitmap;
  FileName: string;
begin
  case Id of
    ID_MODE..ID_MODE + 3:
      begin
        if (Id - ID_MODE = 3) and (FMode <> 3) then FClock := Hour;
        FMode := Id - ID_MODE;
      end;
    ID_TOGGLE..ID_TOGGLE + 3:
      FShow[Id - ID_TOGGLE] := not FShow[Id - ID_TOGGLE];
    ID_BOAT_DEC:
      if Length(FBoats) > 0 then SetLength(FBoats, Length(FBoats) - 1);
    ID_BOAT_INC:
      if Length(FBoats) < MAX_BOATS then AddBoatRandom;
    ID_VIS_DEC:
      FVisitorTarget := Max(0, FVisitorTarget - 4);
    ID_VIS_INC:
      FVisitorTarget := Min(MAX_WALKERS, FVisitorTarget + 4);
    ID_NEW:
      begin
        FSeed := 1 + Integer(GetTickCount64 mod 99999);
        BuildScene;
        InitLife;
        ShowToast(Format('New park, seed %d', [FSeed]));
      end;
    ID_SAVE:
      begin
        FileName := ExtractFilePath(ParamStr(0)) +
          Format('park_%d_%s.png', [FSeed, FormatDateTime('hhnnss', Now)]);
        Part := FBack.GetPart(Rect(0, 0, SW * PX, SH * PX));
        try
          Part.SaveToFile(FileName);
        finally
          Part.Free;
        end;
        ShowToast('Saved ' + ExtractFileName(FileName));
      end;
  end;
end;

procedure TMainForm.TimerTick(Sender: TObject);
begin
  Step;
  if (FSnapFile <> '') and (FTick >= FSnapFrames) then
  begin
    FTimer.Enabled := False;
    RenderAll;
    FBack.SaveToFile(FSnapFile);
    Close;
    Exit;
  end;
  Invalidate;
end;

procedure TMainForm.Paint;
var
  T: QWord;
begin
  RenderAll;
  FBack.Draw(Canvas, 0, 0, True);
  Inc(FFpsFrames);
  T := GetTickCount64;
  if T - FFpsTime >= 1000 then
  begin
    FFps := Double(FFpsFrames) * 1000 / Double(T - FFpsTime);
    FFpsFrames := 0;
    FFpsTime := T;
  end;
end;

procedure TMainForm.EraseBackground(DC: HDC);
begin
  // everything is painted from FBack
end;

procedure TMainForm.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Id: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  Id := ItemAt(X, Y);
  if Id <> FHover then
  begin
    FHover := Id;
    if Id > 0 then Cursor := crHandPoint else Cursor := crDefault;
  end;
end;

procedure TMainForm.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  Id: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  Id := ItemAt(X, Y);
  if Id > 0 then
    HandleItem(Id)
  else if (X < SW * PX) and (Y < SH * PX) then
  begin
    if Length(FBoats) >= MAX_BOATS then
      ShowToast('The lake is full')
    else if CanBoat(X div PX, Y div PX) then
      AddBoat(X div PX, Y div PX)
    else
      ShowToast('Boats need open water');
  end;
end;

constructor TMainForm.Create(AOwner: TComponent);
var
  I: Integer;
  S: string;
begin
  inherited CreateNew(AOwner);
  Caption := 'Sakura Lake Park - BGRABitmap';
  BorderStyle := bsSingle;
  BorderIcons := [biSystemMenu, biMinimize];
  Position := poScreenCenter;
  ClientWidth := SW * PX + PANEL_W;
  ClientHeight := SH * PX;
  FStatic := TBGRABitmap.Create(SW, SH);
  FFrame := TBGRABitmap.Create(SW, SH);
  FBack := TBGRABitmap.Create(SW * PX + PANEL_W, SH * PX);
  FSeed := 2026;
  FMode := 3;
  FClock := 10;
  FVisitorTarget := 36;
  for I := 0 to 3 do
    FShow[I] := True;
  FFpsTime := GetTickCount64;

  for I := 1 to ParamCount do
  begin
    S := ParamStr(I);
    if Pos('--seed=', S) = 1 then FSeed := StrToIntDef(Copy(S, 8, 20), FSeed)
    else if Pos('--mode=', S) = 1 then FMode := EnsureRange(StrToIntDef(Copy(S, 8, 20), 3), 0, 3)
    else if Pos('--hour=', S) = 1 then FClock := StrToFloatDef(Copy(S, 8, 20), FClock)
    else if Pos('--snapshot=', S) = 1 then FSnapFile := Copy(S, 12, MaxInt)
    else if Pos('--after=', S) = 1 then FSnapFrames := Round(StrToFloatDef(Copy(S, 9, 20), 0) * 30);
  end;

  BuildScene;
  InitLife;

  FTimer := TTimer.Create(Self);
  FTimer.Interval := 33;
  FTimer.OnTimer := @TimerTick;
  FTimer.Enabled := True;
end;

destructor TMainForm.Destroy;
begin
  FTimer.Enabled := False;
  FStatic.Free;
  FFrame.Free;
  FBack.Free;
  inherited Destroy;
end;

end.
