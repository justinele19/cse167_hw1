import hw1_common;

// is p inside a circle
bool inside_circle(Circle c, float2 p) {
    return length(p - c.center) <= c.radius;
}

// is p on a circle's stroke
bool on_circle_stroke(Circle c , float stroke_width, float2 p) {
    float dist_to_center = length(p - c.center);
    return abs(dist_to_center - c.radius) <= 0.5 * stroke_width; 
}

// is p inside a closed polyline
bool inside_polyline(StructuredBuffer<float2> points, int begin, int end, float2 p) {
    int n = end - begin;   // how many points
    int signed_hits = 0; 

    // visit every edge
    for (int i = 0; i < n; i++) {
        float2 A = points[begin + i];
        float2 B = points[begin + (i + 1) % n];

        if ((A.y > p.y) != (B.y > p.y)){
            float x_cross = A.x + (p.y - A.y) * (B.x - A.x) / (B.y - A.y);
            if (x_cross > p.x) {
                signed_hits += (B.y > A.y) ? 1 : -1;
            }
        }
    }

    return signed_hits != 0;
}

// is p on a polyline's stroke
bool on_polyline_stroke(StructuredBuffer<float2> points, int begin, int end, 
                        bool closed, float stroke_width, float2 p) {
    int n = end - begin;
    float half_w2 = 0.25 * stroke_width * stroke_width; 

    int num_segs = closed ? n : n - 1;
    for (int i = 0; i < num_segs; i++){
            float2 A = points[begin + i];
            float2 AB = points[begin + (i + 1) % n] - A;    // vector from A to B
            float len2 = dot(AB, AB);

            if (len2 > 0) {
                float t = dot(p - A, AB) / len2;
                if (t >= 0 && t <= 1) {
                    float2 d = p - (A + t * AB);
                    if (dot(d, d) <= half_w2) return true;
                }
            }  
    }

    // round joints
    int first = closed ? 0 : 1;
    int last = closed ? n : n - 1;
    for (int i = first; i < last; i++) {
            float2 d = p - points[begin + i];
            if (dot(d, d) <= half_w2) return true;
    }

    return false; 
}

float3 shade(float2 p,
             float3 background,
             StructuredBuffer<Shape> shapes,
             int num_shapes,
             StructuredBuffer<Circle> circles,
             StructuredBuffer<Polyline> polylines,
             StructuredBuffer<float2> points) {
    float3 color = background;

    for (int s = num_shapes - 1; s >= 0; s--) {
        Shape shape = shapes[s];
        float2 q = mul(shape.world_to_obj, float3(p, 1.0)).xy;

        bool hit_fill = false;
        bool hit_stroke = false;

        if (shape.type == ShapeType.Circle) {
            Circle c = circles[shape.index];
            hit_fill = shape.use_fill && inside_circle(c, q);
            hit_stroke = shape.use_stroke && on_circle_stroke(c, shape.stroke_width, q);
        }
        else if (shape.type == ShapeType.Polyline) {
            Polyline pl = polylines[shape.index];
            hit_fill = shape.use_fill && pl.closed && inside_polyline(points, pl.pts_begin, pl.pts_end, q);
            hit_stroke = shape.use_stroke && on_polyline_stroke(points, pl.pts_begin, pl.pts_end, pl.closed, shape.stroke_width, q);
        }

        // NEW for part 7, then in part 6
        if (hit_fill) {
            color = lerp(color, shape.fill_rgba.xyz, shape.fill_rgba.w);
        }
        if (hit_stroke) {
            color = lerp(color, shape.stroke_rgba.xyz, shape.stroke_rgba.w);
        }
    }
    return color;
}

[shader("compute")]
[numthreads(8, 8, 1)]
void compute_main(uint2 tid : SV_DispatchThreadID,
                  uniform float3 background,
                  uniform int samples_per_axis,
                  StructuredBuffer<Shape> shapes,
                  uniform int num_shapes,
                  StructuredBuffer<Circle> circles,
                  StructuredBuffer<Polyline> polylines,
                  StructuredBuffer<QuadraticBezier> /*quadratic_beziers*/, // ignore for now
                  StructuredBuffer<float2> points,
                  RWTexture2D<float4> image) {
    uint width, height;
    image.GetDimensions(width, height);
    if (tid.x >= width || tid.y >= height) {
        return;
    }

    // TODO: your code here
    int N = max(samples_per_axis, 1);
    float3 sum = float3(0);

    for (int j = 0; j < N; j++) {
        for (int i = 0; i < N; i++) {
            float sx = tid.x + (i + 0.5) / N;
            float sy = tid.y + (j + 0.5) / N;

            float2 p = float2(sx, float(height) - sy);

            sum += shade(p, background, shapes, num_shapes, circles, polylines, points);
        }
    }

    float3 color = sum / float(N * N);
    image[tid] = float4(color, 1.0);
}

