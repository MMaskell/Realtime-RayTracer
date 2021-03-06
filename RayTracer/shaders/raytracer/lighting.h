#ifndef AMBIENT
#define AMBIENT vec3(0.1, 0.1, 0.1)
#endif
//Adds lighting to the pixel
void addLighting(inout vec3 lightColour, Light l, Collision c, vec3 rayDirection);
//Applies lighting to the pixel at 1/fraction the normal brightness
void applyLighting(inout vec3 lightColour, vec3 lightDir, vec3 norm, vec3 rayDirection, Light l, float hitShininess, vec3 hitColour, float dist, float fraction);