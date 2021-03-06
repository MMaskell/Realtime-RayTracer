// /*DEBUG*/ => //*DEBUG*/ Toggles a debug line

bool hasCollision(vec3 rayOrigin, vec3 rayDirection, float minDist, float maxDist){
	//Loop through each plane
	for(int i=0; i<planes.length(); i++){
		if(hasPlaneCollision(planes[i], rayOrigin, rayDirection, minDist, maxDist)) {
			return true;
		}
	}
#ifdef DONT_USE_GRID
	for(int i = 0; i < spheres.length(); i++){
		if(hasSphereCollision(spheres[i], rayOrigin, rayDirection, minDist, maxDist)) {
			return true;
		}
	}
#else
	//Loop through each sphere
	int listStart;
	int listEnd;
	DDA dda;
	if(initSphereListRay(rayOrigin, rayDirection, dda, listStart, listEnd)){
		while(getNextSphereList(dda, listStart, listEnd)){
			for(int i = listStart; i < listEnd; i++){
				if(hasSphereCollision(spheres[sphereLists[i]], rayOrigin, rayDirection, minDist, maxDist)) {
					return true;
				}
			}
		}
	}
#endif
	//Loop through each triangle
#ifdef INGORE_TRIS
		for(int i=0; i<triangles.length(); i++){
		if(hasTriangleCollision(triangles[i], rayOrigin, rayDirection, minDist, maxDist)) {
			return true;
		}
	}
#endif
	return false;
}

Collision getCollision(vec3 rayOrigin, vec3 rayDirection) {
	Collision c;
#ifdef DRAW_REGGRID
	c.dbgColour = vec3(0.0, 0.0, 0.0);
#endif
	//Start with infinite distance collision
	c.dist = 1.0 / 0.0;
	c.hit = false;
#ifdef DONT_USE_GRID
	for(int i=0; i<spheres.length(); i++) {
		getSphereCollision(spheres[i], rayOrigin, rayDirection, c);
	}
#else
	//Loop through each sphere
	int listStart;
	int listEnd;
	DDA dda;
	//Track if a collision was made, if so no need to continue traversing grid
	bool hitSphere = false;
	if(initSphereListRay(rayOrigin, rayDirection, dda, listStart, listEnd)){
		while(getNextSphereList(dda, listStart, listEnd) && !hitSphere){
#ifdef DRAW_REGGRID
			c.dbgColour += vec3(0.1, 0.1, 0.1);
#endif
			for(int i=listStart; i<listEnd; i++){
				hitSphere = (getSphereCollision(spheres[sphereLists[i]], rayOrigin, rayDirection, c) && c.dist < dda.distToEdge) || hitSphere;
#ifndef EARLY_GRID_EXIT
				hitSphere = false;
#endif
			}
		}
	}
#endif
	//Loop through each plane
	for(int i=0; i<planes.length(); i++){
		getPlaneCollision(planes[i], rayOrigin, rayDirection, c);
	}
	//Loop through each triangle
	for(int i=0; i<triangles.length(); i++){
		getTriangleCollision(triangles[i], rayOrigin, rayDirection, c);
	}
	return c;
}

vec3 getPixelColourReflectAndRefract(vec3 rayOrigin, vec3 rayDirection) {
	vec3 pixelColour = vec3(0.0, 0.0, 0.0);
	struct AdditionalRay {
		vec3 rayOrigin;
		vec3 rayDirection;
		float contr;
	};
	struct Iteration {
		AdditionalRay rays[2];
		int numRays;
	};
	Iteration iterations[MAX_DEPTH];
	int numIterations = 1;
	int numReflect = 0;
	int numRefract = 0;
	AdditionalRay primaryRay;
	primaryRay.rayOrigin = rayOrigin;
	primaryRay.rayDirection = rayDirection;
	primaryRay.contr = 1.0;
	Iteration firstIter;
	firstIter.rays[0] = primaryRay;
	firstIter.numRays = 1;
	iterations[0] = firstIter;
	int iterExplored = 0;
	while (numIterations > 0 && iterExplored < MAX_DEPTH) {
		//Pop ray off stack
		numIterations--;
		Iteration it = iterations[numIterations];
		//For each ray in current iteration, explore rays and add new rays to list
		for(int i = 0; i < it.numRays; i++) {
			iterExplored++;
			AdditionalRay ray = it.rays[i];
			Iteration nextIter;
			nextIter.numRays = 0;
			//Find collision
			Collision col = getCollision(ray.rayOrigin, ray.rayDirection);
			//If nothing hit, add the sky
			if (!col.hit) {
				pixelColour += SKY_COLOR * ray.contr;
				continue;
			}
			//Get material of collided object
			Material mat = materials[col.material];
			float startRef = 1.0;
			float endRef = mat.refIndex;
			//Flip normal if hitting back of surface
			if(dot(col.norm, rayDirection) > 0) {
				col.norm *= -1;
				startRef = mat.refIndex;
				endRef = 1.0;
			}
			//Get the proportion of light that is reflected
#ifndef IGNORE_FRESNEL
			float reflectAmount = getFresnel(startRef, endRef, ray.rayDirection, col.norm, mat.reflection);
#else
			float reflectAmount = mat.reflection;
#endif
			float transmitAmount = 1.0 - reflectAmount;

			//If object is solid apply phong lighting
			if (mat.opaque != 0) {
#ifdef DONT_DRAW_LIGHTS
				vec3 lightColour = mat.colour;
#else
				vec3 lightColour = AMBIENT;//vec3(0.0, 0.0, 0.0);
				for(int j=0;j<lights.length(); j++){
					addLighting(lightColour, lights[j], col, ray.rayDirection);
				}
#endif
#ifdef DRAW_REGGRID
				pixelColour += lightColour * transmitAmount * ray.contr + col.dbgColour;
#else
				pixelColour += lightColour * transmitAmount * ray.contr;
#endif
			} else if (ray.contr * transmitAmount > MIN_CONTR && numRefract < MAX_REFRACT) {
#ifdef DEBUG_REFRACT
				pixelColour += vec3(0.1, 0.0, 0.0);
#endif
				numRefract++;
				//Apply refraction
				AdditionalRay refractRay;
				//Check arguments are correct way round
				refractRay.rayDirection = refract(ray.rayDirection, col.norm, startRef / endRef);
				refractRay.rayOrigin = col.pos + refractRay.rayDirection * BIAS;
				refractRay.contr = ray.contr * transmitAmount;
				//refractRay.refIndex = mat.refIndex;
				//Push new ray onto stack
				nextIter.rays[nextIter.numRays] = refractRay;
				nextIter.numRays++;
				//TODO: Apply Beer's law here
			}
			if (ray.contr * reflectAmount > MIN_CONTR && numReflect < MAX_REFLECT) {
#ifdef DEBUG_REFLECT
				pixelColour += vec3(0.0, 0.0, 0.1);
#endif
				numReflect++;
				//Apply Reflection
				AdditionalRay reflectRay;
				reflectRay.rayDirection = reflect(ray.rayDirection, col.norm);
				reflectRay.rayOrigin = col.pos + reflectRay.rayDirection * BIAS;
				reflectRay.contr = ray.contr * reflectAmount;
				//reflectRay.refIndex = ray.refIndex;
				//Push new ray onto stack
				nextIter.rays[nextIter.numRays] = reflectRay;
				nextIter.numRays++;
			}
			//Add next iteration to list
			if(numIterations < MAX_DEPTH && nextIter.numRays > 0) {
				iterations[numIterations] = nextIter;
				numIterations++;
			}
		}
	}
	return pixelColour;
}

float getFresnel(float currentInd, float newInd, vec3 normal, vec3 incident, float reflectivity) {
	if (reflectivity == 0.0) {
		return 0.0;
	}
	float r0 = (currentInd - newInd) / (currentInd + newInd);
	r0 *= r0;
	float cosX = -dot(normal, incident);
	if (currentInd > newInd) {
		float ratio = currentInd / newInd;
		float sinT2 = ratio * ratio * (1.0 - cosX * cosX);
		if (sinT2 > 1.0) {
			return 1.0;
		}
		cosX = sqrt(1.0 - sinT2);
	}
	float x = 1.0 - cosX;
	
	return reflectivity + (1.0 - reflectivity) * (r0 + (1.0 - r0) * x * x * x * x * x);
}
