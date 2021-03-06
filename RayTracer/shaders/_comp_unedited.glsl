#version 430
#extension GL_ARB_compute_variable_group_size : enable
//Increasing this DESTROYS the framerate (Likely a result of less being done in parallel)
#define GROUP_SIZE 1
layout(local_size_x = GROUP_SIZE, local_size_y = GROUP_SIZE, local_size_z = 1) in;

//Prevent reflected rays colliding with the object they originated from
#define BIAS 0.001

#define NUM_SHADOW_RAYS 1

#define SKY_COLOR vec3(0.529, 0.808, 0.980)

//Structures must align to a multiple of 4 bytes

struct Sphere {
	vec3 pos;
	float radius;
	vec3 colour;
	float shininess;
};

struct Plane {
	vec3 pos;
	float shininess;
	vec3 norm;
	float paddingA;
	vec3 colour;
	float paddingB;
};

//Fun fact, not padding vec3s and putting it at the end breaks everything

struct Light {
	vec3 pos;
	float isDirectional;
	vec3 colour;
	float radius;
	float constant;
	float linear;
	float quadratic;
	//Pre calc maximum distance light is visible from
	float maxDist;
};

//The image being written to
layout(rgba32f, binding = 0) uniform writeonly image2D imgOut;
/*
Spheres: A list of every sphere in the scene
SphereGrid: A list of the start and end positions of each grids list of contained sphers
SphereList: A concatanation of lists of spheres contained within the grids
*/
layout(std140, binding = 1) buffer SphereBuffer {
	Sphere spheres[];
};
//WHAT IS WRONG WITH YOU OPENGL, WHY DOES SETTING THIS TO std140 MAKE YOU IGNORE 3/4 OF THE DATA
layout(std430, binding = 2) buffer GridBuffer {
	int sphereGrid[];
};

layout(std430, binding = 3) buffer ListBuffer {
	int sphereLists[];
};

layout(std140, binding = 4) buffer PlaneBuffer {
	Plane planes[];
};

layout(std140, binding = 5) buffer LightBuffer {
	Light lights[];
};

uniform float twiceTanFovY;
uniform float cameraWidth;
uniform float cameraHeight;
uniform mat4 cameraMatrix;

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

uniform bool debug;


//DDA variables
struct DDA {
	int stepX;
	int stepY;
	int stepZ;
	float deltaX;
	float deltaY;
	float deltaZ;
	int gridX;
	int gridY;
	int gridZ;
	float maxX;
	float maxY;
	float maxZ;
	bool firstSphereIt;
};

//Applies lighting to the pixel at 1/fraction the normal brightness
void applyLighting(inout vec3 lightColour, vec3 lightDir, vec3 hitNorm, vec3 rayDirection, Light l, float hitShininess, vec3 hitColour, float dist, float fraction);

//Gets the pixel colour where the ray hits
vec3 getPixelColour(vec3 rayOrigin, vec3 rayDirection);

//Returns if the ray hits anything
bool hasCollision(vec3 rayOrigin, vec3 rayDirection, float minDist, float maxDist);

//Gets the next grid that contains a possible collision
bool getNextSphereList(inout DDA dda, inout int listStart, inout int listEnd);

//Resets the grid traversal algorithm
bool initSphereListRay(vec3 rayOrigin, vec3 rayDirection, inout DDA dda, inout int listStart, inout int listEnd);

void main(){
	//Get the position of the current pixel
	ivec2 pixelPos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 screenSize = imageSize(imgOut);
	//Calculate ray
	//Use view matrix to set origin
	vec3 rayOrigin = vec3(cameraMatrix * vec4(0.0, 0.0, 0.0, 1.0));
	//Convert pixel position to world space
	float x = cameraWidth * (pixelPos.x + 0.5) / screenSize.x - cameraWidth * 0.5;
	float y = cameraHeight * (pixelPos.y + 0.5) / screenSize.y - cameraHeight * 0.5;
	float z = cameraHeight / twiceTanFovY;
	//Apply view matrix to direction
	vec3 rayDirection = normalize(mat3(cameraMatrix) * vec3(x, y, z));
	//Fire ray
	vec3 pixelColour = getPixelColour(rayOrigin, rayDirection);
	imageStore(imgOut, pixelPos, vec4(pixelColour, 1.0));
}

//Finds the colour at the point the ray hits
vec3 getPixelColour(vec3 rayOrigin, vec3 rayDirection){
	//
	//Initial ray intersections
	//
	float d = -1;
	vec3 hitAt;
	vec3 hitNorm;
	vec3 hitColour;
	float hitShininess;
	//Loop through each sphere
	int listStart;
	int listEnd;
	DDA dda;
	
	//vec3 debugColour = vec3(0.0, 0.0, 0.0);
	bool gridNotHit = true;
	if(initSphereListRay(rayOrigin, rayDirection, dda, listStart, listEnd)){
		while(getNextSphereList(dda, listStart, listEnd) && gridNotHit){
			//debugColour += vec3(0.1, 0.1, 0.1);
			for(int i=listStart; i<listEnd; i++){
				Sphere s = spheres[sphereLists[i]];
				// P = rO + t(rD) //Ray equation
				// r = |P - C|    //Sphere equation
				////After much rearranging we get:
				// t = -b +/- sqrt(b*b - c)
				// Where:
				// b = (rO - C) . rD
				// c = (rO - C).(rO - C) - r*r
				// If b * b - c < 0: No Solutions
				// If b * b - c = 0: 1 Solution
				// If b * b - c > 0: 2 Solutions
				vec3 rOC = rayOrigin - s.pos;
				float b = dot(rOC, rayDirection);
				float c = dot(rOC, rOC) - s.radius * s.radius;
				float disc = b * b - c;
				//Check for solution
				if(disc >= 0.0){
					float rt = sqrt(disc);
					float first = -b + rt;
					float second = -b - rt;
					float closest = min(first, second);
					//Closest is behind camera, try other one
					if(closest < 0.0){
						closest = max(first, second);
					}
					if(closest >= 0.0 && (d<0.0 || d>closest)){
						d = closest;
						hitAt = rayOrigin + d * rayDirection;
						hitNorm = normalize(hitAt - s.pos);
						hitColour = s.colour;
						hitShininess = s.shininess;
						gridNotHit = false;
					}
				}
			}
		}
	}
	//Loop through each plane
	for(int i=0; i<planes.length(); i++){
		Plane p = planes[i];
		// P = rO + t(rD)
		// 0 = N . (P - p0)
		// 0 = N . (p0 - rO + t(rD))
		// t = (p0 - rO).N / (rD.N)
		// If rD.N = 0: Parallel (For this treat as no intersection)
		// If t < 0: Behind ray origin
		float rDN = dot(rayDirection, p.norm);
		//Check not zero (or very close to)
		if(abs(rDN)>0.0001 && dot(-rayDirection, p.norm) > 0.0) {
			float t = dot((p.pos - rayOrigin), p.norm) / rDN;
			if(t > 0.0 && (d < 0.0 || t < d)){
				d = t;
				hitAt = rayOrigin + d * rayDirection;
				hitNorm = p.norm;
				hitShininess = p.shininess;
				hitColour = p.colour;
			}
		}
	}
	//No collisions just draw the sky
	if(d < 0){
		//return SKY_COLOR + debugColour;
		return SKY_COLOR;
	}
	//
	//Lighting
	//
	vec3 lightColour = vec3(0.0, 0.0, 0.0);//Add ambient here?
	//Loop through each light to calculate lighting
	for(int i=0;i<lights.length(); i++){
		Light l = lights[i];
		vec3 lightDir;
		if(l.isDirectional>0.0){
			lightDir = -l.pos;
		} else {
			lightDir = l.pos - hitAt;
		}
		float dist = length(lightDir);
		lightDir /= dist; //Normalize
		//For efficiency don't calculate effect of distant light sources
		//Also check for shadows here
		if((l.isDirectional>0.0 || dist < l.maxDist)) {
#if (NUM_SHADOW_RAYS <= 0)
			applyLighting(lightColour, lightDir, hitNorm, rayDirection, l, hitShininess, hitColour, dist, 1.0);
#endif
#if ((NUM_SHADOW_RAYS > 0) && (NUM_SHADOW_RAYS % 2 == 1))
			float frac;
			float maxDist;
			if(l.isDirectional>0.0) {
				frac = 1.0;
				maxDist = -1.0;
			} else {
				frac = NUM_SHADOW_RAYS * NUM_SHADOW_RAYS;
				maxDist = dist;
			}
			if(!hasCollision(hitAt, lightDir, BIAS, maxDist)){
				applyLighting(lightColour, lightDir, hitNorm, rayDirection, l, hitShininess, hitColour, dist, frac);
			}
#endif
/*
Range from -LR to +LR
Fire ray in centre
For NUM_SHADOW_RAYS/2 Fire ray in neg from centre at interval of LR / NUM_SHADOW_RAYS/2 
*/
#if (NUM_SHADOW_RAYS > 1)
			if(l.isDirectional <= 0.0){
				vec3 lightUp = vec3(0.0, 1.0, 0.0);
				vec3 lightRight = cross(lightDir, lightUp);
				lightUp = cross(lightRight, lightDir);
				int halfNumRays = NUM_SHADOW_RAYS/2;
				lightRight *= l.radius / halfNumRays;
				lightUp *= l.radius / halfNumRays;
				for(int x = 1; x <= halfNumRays; x++) {
					for(int y = 1; y <= halfNumRays; y++) {
						vec3 newDir = (l.pos + lightRight * x + lightUp * y) - hitAt;
						dist = length(newDir);
						newDir /= dist;
						if(!hasCollision(hitAt, newDir, BIAS, dist)){
							applyLighting(lightColour, newDir, hitNorm, rayDirection, l, hitShininess, hitColour, dist, NUM_SHADOW_RAYS * NUM_SHADOW_RAYS);
						}
						newDir = (l.pos - lightRight * x + lightUp * y) - hitAt;
						dist = length(newDir);
						newDir /= dist;
						if(!hasCollision(hitAt, newDir, BIAS, dist)){
							applyLighting(lightColour, newDir, hitNorm, rayDirection, l, hitShininess, hitColour, dist, NUM_SHADOW_RAYS * NUM_SHADOW_RAYS);
						}
						newDir = (l.pos + lightRight * x - lightUp * y) - hitAt;
						dist = length(newDir);
						newDir /= dist;
						if(!hasCollision(hitAt, newDir, BIAS, dist)){
							applyLighting(lightColour, newDir, hitNorm, rayDirection, l, hitShininess, hitColour, dist, NUM_SHADOW_RAYS * NUM_SHADOW_RAYS);
						}
						newDir = (l.pos - lightRight * x - lightUp * y) - hitAt;
						dist = length(newDir);
						newDir /= dist;
						if(!hasCollision(hitAt, newDir, BIAS, dist)){
							applyLighting(lightColour, newDir, hitNorm, rayDirection, l, hitShininess, hitColour, dist, NUM_SHADOW_RAYS * NUM_SHADOW_RAYS);
						}
					}
				}
			}
#endif
		}
	}
	//return lightColour + debugColour;
	return lightColour;
}

void applyLighting(inout vec3 lightColour, vec3 lightDir, vec3 hitNorm, vec3 rayDirection, Light l, float hitShininess, vec3 hitColour, float dist, float fraction){
	float diff = max(0.0, dot(hitNorm, lightDir));
	vec3 halfwayDir = normalize(lightDir - rayDirection);
	float spec = pow(max(dot(hitNorm, halfwayDir), 0.0), hitShininess);
	float att = 1.0 / (l.constant + l.linear * dist + 
		l.quadratic * (dist * dist));
	//Directional light does not dim with distance
	if(l.isDirectional > 0.0) {
		att = 1.0;
	}
	lightColour += (hitColour * diff + spec) * l.colour * att / fraction;
}

bool hasCollision(vec3 rayOrigin, vec3 rayDirection, float minDist, float maxDist){
	//Loop through each plane
	for(int i=0; i<planes.length(); i++){
		Plane p = planes[i];
		// P = rO + t(rD)
		// 0 = N . (P - p0)
		// 0 = N . (p0 - rO + t(rD))
		// t = (p0 - rO).N / (rD.N)
		// If rD.N = 0: Parallel (For this treat as no intersection)
		// If d < 0: Behind ray origin
		float rDN = dot(rayDirection, p.norm);
		//Check not zero (or very close to)
		if(abs(rDN)>0.0001){
			float t = dot((p.pos - rayOrigin), p.norm) / rDN;
			if(t > minDist && (t <= maxDist || maxDist < 0)){
				return true;
			}
		}
	}
	//Loop through each sphere
	int listStart;
	int listEnd;
	DDA dda;
	if(initSphereListRay(rayOrigin, rayDirection, dda, listStart, listEnd)){
		while(getNextSphereList(dda, listStart, listEnd)){
			for(int i=listStart; i<listEnd; i++){
				Sphere s = spheres[sphereLists[i]];
				//Sphere s = spheres[i];
				// P = rO + t(rD) //Ray equation
				// r = |P - C|    //Sphere equation
				////After much rearranging we get:
				// t = -b +/- sqrt(b*b - c)
				// Where:
				// b = (rO - C) . rD
				// c = (rO - C).(rO - C) - r*r
				// If b * b - c < 0: No Solutions
				// If b * b - c = 0: 1 Solution
				// If b * b - c > 0: 2 Solutions
				vec3 rOC = rayOrigin - s.pos;
				float b = dot(rOC, rayDirection);
				float c = dot(rOC, rOC) - s.radius * s.radius;
				//Check for solution
				float disc = b * b - c;
				//Check for solution
				if(disc >= 0.0){
					float rt = sqrt(disc);
					float first = -b + rt;
					if(first >= minDist && (first <= maxDist || maxDist < 0)){
						return true;
					}
				}
			}
		}
	}
	return false;
}


/*
Store:
First vertical cut: tMaxX
First horizontal cut: tMaxY
How far to move before the ray has 
travelled a horizontal distance of one cell width: DeltaX
How far to move before the ray has 
travelled a vertical distance of one cell height: DeltaY

list= NIL;
do  {
	if(tMaxX < tMaxY) {
		if(tMaxX < tMaxZ) {
			X= X + stepX;
			if(X == justOutX)
				return(NIL); 
			tMaxX= tMaxX + tDeltaX;
		} else  {
			Z= Z + stepZ;
			if(Z == justOutZ)
				return(NIL);
			tMaxZ= tMaxZ + tDeltaZ;
		}
	} else  {
		if(tMaxY < tMaxZ) {
			Y= Y + stepY;
			if(Y == justOutY)
				return(NIL);
			tMaxY= tMaxY + tDeltaY;
		} else  {
			Z= Z + stepZ;
			if(Z == justOutZ)
				return(NIL);
			tMaxZ= tMaxZ + tDeltaZ;
		}
	}
	list= ObjectList[X][Y][Z];
} while(list == NIL);

*/

bool distToAABB(vec3 rayOrigin, vec3 rayDirection, inout float dist) {
	vec3 dirInv = vec3(1.0 / rayDirection.x, 1.0 / rayDirection.y, 1.0 / rayDirection.z);
    float tx1 = (gridMinX - rayOrigin.x)*dirInv.x;
    float tx2 = (gridMaxX - rayOrigin.x)*dirInv.x;
 
    float tmin = min(tx1, tx2);
    float tmax = max(tx1, tx2);
 
    float ty1 = (gridMinY - rayOrigin.y)*dirInv.y;
    float ty2 = (gridMaxY - rayOrigin.y)*dirInv.y;
 
    tmin = max(tmin, min(ty1, ty2));
    tmax = min(tmax, max(ty1, ty2));
	
	float tz1 = (gridMinZ - rayOrigin.z)*dirInv.z;
    float tz2 = (gridMaxZ - rayOrigin.z)*dirInv.z;
 
    tmin = max(tmin, min(tz1, tz2));
    tmax = min(tmax, max(tz1, tz2));
	
	dist = tmin;
    return tmax >= tmin && tmax > 0.0;
}

bool initSphereListRay(vec3 rayOrigin, vec3 rayDirection, inout DDA dda, inout int listStart, inout int listEnd) {
	listStart = 0;
	listEnd = 0;
	dda.stepX = rayDirection.x > 0 ? 1 : -1;
	dda.stepY = rayDirection.y > 0 ? 1 : -1;
	dda.stepZ = rayDirection.z > 0 ? 1 : -1;

	//Keep ray in bounds
	/*
	//Fix x position
	if((rayOrigin.x >= gridMaxX && rayDirection.x >= 0) || (rayOrigin.x <= gridMinX && rayDirection.x <= 0)) {
		return false;
	}
	if(dda.stepX == 1 && rayOrigin.x < gridMinX){
		rayOrigin += rayDirection * ((gridMinX - rayOrigin.x) / rayDirection.x);
	} else if(dda.stepX == -1 && rayOrigin.x > gridMaxX) {
		rayOrigin += rayDirection * ((gridMaxX - rayOrigin.x) / rayDirection.x);
	}
	//Fix y position
	if ((rayOrigin.y >= gridMaxY && rayDirection.y >= 0) || (rayOrigin.y <= gridMinY && rayDirection.y <= 0)) {
		return false;
	}
	if(dda.stepY == 1 && rayOrigin.y < gridMinY){
		rayOrigin += rayDirection * ((gridMinY - rayOrigin.y) / rayDirection.y);
	} else if(dda.stepY == -1 && rayOrigin.y > gridMaxY) {
		rayOrigin += rayDirection * ((gridMaxY - rayOrigin.y) / rayDirection.y);
	}
	//Fix z position
	if ((rayOrigin.z >= gridMaxZ && rayDirection.z >= 0) || (rayOrigin.z <= gridMinZ && rayDirection.z <= 0)) {
		return false;
	}
	if(dda.stepZ == 1 && rayOrigin.z < gridMinZ){
		rayOrigin += rayDirection * ((gridMinZ - rayOrigin.z) / rayDirection.z);
	} else if(dda.stepZ == -1 && rayOrigin.z > gridMaxZ){
		rayOrigin += rayDirection * ((gridMaxZ - rayOrigin.z) / rayDirection.z);
	}
	*/
	//*
	float dist;
	if(distToAABB(rayOrigin, rayDirection, dist)){
		rayOrigin = rayOrigin + dist * rayDirection;
	} else {
		return false;
	}
	//*/
	
	dda.deltaX = sizeX / rayDirection.x;
	dda.deltaY = sizeY / rayDirection.y;
	dda.deltaZ = sizeZ / rayDirection.z;
	
	//Make negative directions positive																									<<<<<FIX FOR REGULAR GRID RENDERING
	dda.deltaX *= dda.stepX;
	dda.deltaY *= dda.stepY;
	dda.deltaZ *= dda.stepZ;
	
	dda.gridX = clamp(int(floor((rayOrigin.x - gridMinX) / sizeX)), 0, numX - 1);
	dda.gridY = clamp(int(floor((rayOrigin.y - gridMinY) / sizeY)), 0, numY - 1);
	dda.gridZ = clamp(int(floor((rayOrigin.z - gridMinZ) / sizeZ)), 0, numZ - 1);
	dda.maxX = ((dda.gridX + max(0, dda.stepX))*sizeX + gridMinX - rayOrigin.x) / rayDirection.x;
	dda.maxY = ((dda.gridY + max(0, dda.stepY))*sizeY + gridMinY - rayOrigin.y) / rayDirection.y;
	dda.maxZ = ((dda.gridZ + max(0, dda.stepZ))*sizeZ + gridMinZ - rayOrigin.z) / rayDirection.z;
	dda.firstSphereIt = true;
	return true;
}
/*
Store index of last sphere
Get first index from previous
If no previous first is 0

LIST_START = Index of first relevant sphere in sphereList
LIST_END = Index of first non relevant sphere in sphereList

If no matches LIST_START = LIST_END

*/
bool getNextSphereList(inout DDA dda, inout int listStart, inout int listEnd) {
	int index;
	if(dda.stepZ != 1 && dda.stepZ != -1 && dda.stepZ != 0) {while(true){}}
	//do {
		if(!dda.firstSphereIt){
			if(dda.maxX < dda.maxY) {
				if(dda.maxX < dda.maxZ) {
					dda.gridX = dda.gridX + dda.stepX;
					if(dda.gridX == numX || dda.gridX == -1)
						return false; 
					dda.maxX = dda.maxX + dda.deltaX;
				} else  {
					dda.gridZ = dda.gridZ + dda.stepZ;
					if(dda.gridZ == numZ || dda.gridZ == -1)
						return false;
					dda.maxZ = dda.maxZ + dda.deltaZ;
				}
			} else  {
				if(dda.maxY < dda.maxZ) {
					dda.gridY = dda.gridY + dda.stepY;
					if(dda.gridY == numY || dda.gridY == -1)
						return false;
					dda.maxY = dda.maxY + dda.deltaY;
				} else  {
					dda.gridZ = dda.gridZ + dda.stepZ;
					if(dda.gridZ == numZ || dda.gridZ == -1)
						return false;
					dda.maxZ = dda.maxZ + dda.deltaZ;
				}
			}
		}
		dda.firstSphereIt = false;
		index = dda.gridX + dda.gridY * numX + dda.gridZ * numX * numY;
		if(index == 0) {
			listStart = 0;
		} else {
			listStart = sphereGrid[index - 1];
		}
		listEnd = sphereGrid[index];
	//} while(listStart == listEnd);
	return true;
}