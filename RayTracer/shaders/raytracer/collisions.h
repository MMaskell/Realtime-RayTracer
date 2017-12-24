uniform int numX;
uniform int numY;
uniform int numZ;
uniform float sizeX;
uniform float sizeY;
uniform float sizeZ;
uniform float gridMinX;
uniform float gridMinY;
uniform float gridMinZ;
uniform float gridMaxX;
uniform float gridMaxY;
uniform float gridMaxZ;

struct Collision {
	float dist;
	vec3 hitAt;
	vec3 hitNorm;
	vec3 hitColour;
	float hitShininess;
	bool hit;
};

//Prevent reflected rays colliding with the object they originated from
#define BIAS 0.001

#define NUM_SHADOW_RAYS 1

#define SKY_COLOR vec3(0.529, 0.808, 0.980)

//Applies lighting to the pixel at 1/fraction the normal brightness
void applyLighting(inout vec3 lightColour, vec3 lightDir, vec3 hitNorm, vec3 rayDirection, Light l, float hitShininess, vec3 hitColour, float dist, float fraction);

//Gets the pixel colour where the ray hits
vec3 getPixelColour(vec3 rayOrigin, vec3 rayDirection);

//Returns if the ray hits anything
bool hasCollision(vec3 rayOrigin, vec3 rayDirection, float minDist, float maxDist);