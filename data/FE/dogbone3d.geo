//==============================================================================
// Gmsh 2D parametric plate mesh
// author: Lloyd Fletcher (scepticalrabbit)
//==============================================================================
// Always set to OpenCASCADE - circles and boolean opts are much easier!
SetFactory("OpenCASCADE");

// Allows gmsh to print to terminal in vscode - easier debugging
General.Terminal = 1;

// View options - not required when
Geometry.PointLabels = 0;
Geometry.CurveLabels = 0;
Geometry.SurfaceLabels = 1;
Geometry.VolumeLabels = 0;

//------------------------------------------------------------------------------
// Variables
file_name = "dogbone3d.msh";

// Variables: Specimen Geometry SS-J3 Specimen
// Overall dimensions of the sample including gripped section
spec_width = 4e-3;
spec_leng = 16e-3;
spec_thick = 0.6e-3;
// Dimensions of the gauge/waisted section of the sample
spec_gauge_width = 1.2e-3;
spec_gauge_leng = 5e-3;
spec_waist_rad = 1.4e-3;
// specPinHoleLSpace = 11.9e-3;
// specPinHoleDiam = 1.5e-3;

// Mesh variables
gauge_leng_divs = 20;
gauge_width_divs = 4;
elem_size = spec_gauge_leng/10;
elem_order = 2;

tol = elem_size/8;

mesh_ref = 3;
spec_thick_layers = 2;

// Calculated variable
shoulder_loc_x = spec_gauge_width/2 + spec_waist_rad;
shoulder_loc_y = spec_gauge_leng/2;
tab_shoulder_leng = spec_leng/2 - spec_gauge_leng/2;

//------------------------------------------------------------------------------
// Geometry Definition
s1 = news;
Rectangle(s1) = {-spec_width/2,-spec_gauge_leng/2,0.0,
                spec_width/2,spec_gauge_leng};
s2 = news;
Rectangle(s2) = {0.0,-spec_gauge_leng/2,0.0,
                spec_width/2,spec_gauge_leng};
s3 = news;
Rectangle(s3) = {-spec_width/2,-spec_leng/2,0.0,
                spec_width/2,tab_shoulder_leng};
s4 = news;
Rectangle(s4) = {0.0,-spec_leng/2,0.0,
                spec_width/2,tab_shoulder_leng};
s5 = news;
Rectangle(s5) = {-spec_width/2,spec_gauge_leng/2,0.0,
                spec_width/2,tab_shoulder_leng};
s6 = news;
Rectangle(s6) = {0.0,spec_gauge_leng/2,0.0,
                spec_width/2,tab_shoulder_leng};

// Merge coincicent edges of the overlapping rectangles
BooleanFragments{ Surface{s1}; Delete; }
{ Surface{s2,s3,s4,s5,s6}; Delete; }

s7 = news;
Rectangle(s7) = {-spec_width-spec_gauge_width/2,-spec_gauge_leng/2,0.0,
                spec_width,spec_gauge_leng};
s8 = news;
Rectangle(s8) = {spec_gauge_width/2,-spec_gauge_leng/2,0.0,
                spec_width,spec_gauge_leng};

c1 = newc;
Circle(c1) = {shoulder_loc_x,shoulder_loc_y,0.0,spec_waist_rad};
cl1 = newcl; Curve Loop(cl1) = {c1};
s10 = news; Plane Surface(s10) = {cl1};

c2 = newc;
Circle(c2) = {-shoulder_loc_x,shoulder_loc_y,0.0,spec_waist_rad};
cl2 = newcl; Curve Loop(cl2) = {c2};
s11 = news; Plane Surface(s11) = {cl2};

c3 = newc;
Circle(c3) = {-shoulder_loc_x,-shoulder_loc_y,0.0,spec_waist_rad};
cl3 = newcl; Curve Loop(cl3) = {c3};
s12 = news; Plane Surface(s12) = {cl3};

c4 = newc;
Circle(c4) = {shoulder_loc_x,-shoulder_loc_y,0.0,spec_waist_rad};
cl4 = newcl; Curve Loop(cl4) = {c4};
s13 = news; Plane Surface(s13) = {cl4};

BooleanDifference{ Surface{s1,s2,s3,s4,s5,s6}; Delete; }
                 { Surface{s7,s8,s10,s11,s12,s13}; Delete; }

//------------------------------------------------------------------------------
// Meshing
MeshSize{ PointsOf{ Surface{:}; } } = elem_size;

Extrude{0.0,0.0,spec_thick}{
    Surface{:}; Layers{spec_thick_layers}; Recombine;
}

//------------------------------------------------------------------------------
// Physical lines and surfaces for export/BCs
Physical Volume("dogbone") = {Volume{:}};

ps1() = Surface In BoundingBox{
    -spec_width-tol,spec_leng/2-tol,-spec_thick-tol,
    spec_width+tol,spec_leng/2+tol,spec_thick+tol};
Physical Surface("bc-top-disp") = {ps1(0),ps1(1)};

ps2() = Surface In BoundingBox{
    -spec_width-tol,-spec_leng/2-tol,-spec_thick-tol,
    spec_width+tol,-spec_leng/2+tol,spec_thick+tol};
Physical Surface("bc-base-disp") = {ps2(0),ps2(1)};

//------------------------------------------------------------------------------
// Global meshing
Mesh.Algorithm = 6;
Mesh.Algorithm3D = 10;

General.NumThreads = num_threads;
Mesh.MaxNumThreads1D = num_threads;
Mesh.MaxNumThreads2D = num_threads;
Mesh.MaxNumThreads3D = num_threads;

Mesh.ElementOrder = elem_order;
Mesh 3;

//------------------------------------------------------------------------------
// Save and exit
Save Str(file_name);
//Exit;




