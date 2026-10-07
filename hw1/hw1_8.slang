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

// Point on one quadratic Bezier curve at parameter t (equation 8)
float2 bezier_eval(float2 p0, float2 p1, float2 p2, float t) {
    float s = 1.0 - t;
    return s * s * p0 + 2.0 * s * t * p1 + t * t * p2;
}

// NEW TO PART 8 
// is p inside a closed chain of Bezier curves
bool inside_bezier(StructuredBuffer<float2> points, int begin, int end, float2 p) {
    int n = end - begin;   
    int m = n / 2;        
    int signed_hits = 0;

    for (int k = 0; k < m; k++) {
        // Curve k uses points 2k, 2k+1, 2k+2 (the last one wraps to point 0)
        float2 p0 = points[begin + 2 * k];
        float2 p1 = points[begin + 2 * k + 1];
        float2 p2 = points[begin + (2 * k + 2) % n];

        // q_y(t) = p.y  rewritten as  a t^2 + b t + c = 0
        float a = p0.y - 2.0 * p1.y + p2.y;
        float b = 2.0 * (p1.y - p0.y);
        float c = p0.y - p.y;

        float2 roots;
        if (!solve_quadratic(a, b, c, roots)) {
            continue;   // curve never reaches this height
        }
        // When a == 0 the solver puts the same single root in both slots,
        // so only look at one of them to avoid counting it twice.
        int num_roots = (a == 0.0) ? 1 : 2;

        for (int r = 0; r < num_roots; r++) {
            float t = roots[r];
            if (t < 0.0 || t >= 1.0) continue;                   
            if (bezier_eval(p0, p1, p2, t).x <= p.x) continue;   

            // Direction of the crossing --> derivative of q_y(t)
            float dy = 2.0 * a * t + b;
            if (dy > 0.0) {
                signed_hits += 1;   // going up
            } else if (dy < 0.0) {
                signed_hits -= 1;   // going down
            }
        }
    }
    return signed_hits != 0;
}

// is p on the stroke of a chain of Bezier curves
bool on_bezier_stroke(StructuredBuffer<float2> points, int begin, int end,
                      bool closed, float stroke_width, float2 p) {
    int n = end - begin;
    int m = closed ? n / 2 : (n - 1) / 2;   
    float half_w2 = 0.25 * stroke_width * stroke_width;

    // curves (flat ends): closest points from the cubic 
    for (int k = 0; k < m; k++) {
        float2 p0 = points[begin + 2 * k];
        float2 p1 = points[begin + 2 * k + 1];
        float2 p2 = points[begin + (2 * k + 2) % n];

        // q(t) = A t^2 + B t + p0
        float2 A = p0 - 2.0 * p1 + p2;
        float2 B = 2.0 * (p1 - p0);
        float2 D = p0 - p;

        // (q(t) - p) . q'(t) = 0  expands to  a t^3 + b t^2 + c t + d = 0
        float a = 2.0 * dot(A, A);
        float b = 3.0 * dot(A, B);
        float c = dot(B, B) + 2.0 * dot(A, D);
        float d = dot(B, D);

        float3 roots;
        int num_roots = solve_cubic(a, b, c, d, roots);
        for (int r = 0; r < num_roots; r++) {
            float t = roots[r];
            // Only points ON the curve count: this gives flat ends
            if (t >= 0.0 && t <= 1.0) {
                float2 diff = bezier_eval(p0, p1, p2, t) - p;
                if (dot(diff, diff) <= half_w2) return true;
            }
        }
    }

    // --- Round joints: where curves meet ---
    // Closed: every curve's start point. Open: only interior ones (p2, p4, ...),
    // so the two free ends stay flat.
    int first = closed ? 0 : 1;
    for (int k = first; k < m; k++) {
        float2 diff = points[begin + 2 * k] - p;
        if (dot(diff, diff) <= half_w2) return true;
    }

    return false;
}

float3 shade(float2 p,
             float3 background,
             StructuredBuffer<Shape> shapes,
             int num_shapes,
             StructuredBuffer<Circle> circles,
             StructuredBuffer<Polyline> polylines,
             StructuredBuffer<QuadraticBezier> quadratic_beziers,
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
        else if (shape.type == ShapeType.QuadraticBezier) {      // NEW
            QuadraticBezier qb = quadratic_beziers[shape.index];
            hit_fill   = shape.use_fill && qb.closed
                         && inside_bezier(points, qb.pts_begin, qb.pts_end, q);
            hit_stroke = shape.use_stroke
                         && on_bezier_stroke(points, qb.pts_begin, qb.pts_end,
                                             qb.closed, shape.stroke_width, q);
        }

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
                  StructuredBuffer<QuadraticBezier> quadratic_beziers,
                  StructuredBuffer<float2> points,
                  RWTexture2D<float4> image) {
    uint width, height;
    image.GetDimensions(width, height);
    if (tid.x >= width || tid.y >= height) {
        return;
    }

    image[tid] = float4(1.0);
    // TODO: your code here
     int N = max(samples_per_axis, 1);
    float3 sum = float3(0);

    for (int j = 0; j < N; j++) {
        for (int i = 0; i < N; i++) {
            float sx = tid.x + (i + 0.5) / N;
            float sy = tid.y + (j + 0.5) / N;

            float2 p = float2(sx, float(height) - sy);

            sum += shade(p, background, shapes, num_shapes, circles, polylines, quadratic_beziers, points);
        }
    }

    float3 color = sum / float(N * N);
    image[tid] = float4(color, 1.0);
}
