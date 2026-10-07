import hw1_common;

[shader("compute")]
[numthreads(8, 8, 1)]
void compute_main(uint2 tid : SV_DispatchThreadID,
                  StructuredBuffer<float2> polyline,
                  uniform int num_polyline,
                  uniform bool is_closed,
                  uniform bool use_fill_color,
                  uniform float3 fill_color,
                  uniform bool use_stroke_color,
                  uniform float3 stroke_color,
                  uniform float stroke_width,
                  RWTexture2D<float4> image) {
    uint width, height;
    image.GetDimensions(width, height);
    if (tid.x >= width || tid.y >= height) {
        return;
    }

    image[tid] = float4(0.5, 0.5, 0.5, 1.0);
    // TODO: your code here
    float2 p = float2(tid.x + 0.5, height - (tid.y + 0.5));  // find pixel center
    
    /** 
        1. find pixel center
        2. from each pixels' center, shoot a ray to the right, but how long of a ray?
            a. use linear system w/ 2 var (s,t) to determine intersection
        3. if within the stroke's width --> fill w/ stroke color
        4. else --> fill w/ fill color 
    **/

    if (is_closed && use_fill_color && num_polyline >= 3)
    {
        int signed_hits = 0;
        for (int i = 0; i < num_polyline; i++)
        {
            float2 A = polyline[i];
            float2 B = polyline[(i + 1) % num_polyline];
            if ((A.y > p.y) != (B.y > p.y)){
                float x_cross = A.x + (p.y - A.y) * (B.x - A.x) / (B.y - A.y);
                if (x_cross > p.x) {
                    signed_hits += (B.y > A.y) ? 1 : -1;
                }
            }
        }
        if (signed_hits != 0){
            image[tid] = float4(fill_color, 1);
        }
    }

    if (use_stroke_color && num_polyline >= 2) {
        float half_w2 = 0.25 * stroke_width * stroke_width;
        bool on_stroke = false;

        int num_segs = is_closed ? num_polyline : num_polyline - 1;
        for (int i = 0; i < num_segs && !on_stroke; i++){
            float2 A = polyline[i];
            float2 AB = polyline[(i + 1) % num_polyline] - A;
            float len2 = dot(AB, AB);
            if (len2 > 0) {
                float t = dot(p - A, AB) / len2;
                if (t >= 0 && t <= 1) {
                    float2 d = p - (A + t * AB);
                    on_stroke = dot(d, d) <= half_w2;
                }
            }  
        }

        // curves
        int first = is_closed ? 0 : 1;
        int last = is_closed ? num_polyline : num_polyline - 1;
        for (int i = first; i < last && !on_stroke; i++) {
            float2 d = p - polyline[i];
            on_stroke = dot(d, d) <= half_w2;
        }

        if (on_stroke) {
        image[tid] = float4(stroke_color, 1);
        }
    
    }

}
