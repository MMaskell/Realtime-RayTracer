//Finds the colour at the point the ray hits
vec3 getPixelColour(vec3 rayOrigin, vec3 rayDirection){
	//
	//Initial ray intersections
	//
	Collision c;
	//Start with infinite distance collision
	c.dist = 1.0 / 0.0;
	c.hit = false;
	//Loop through each sphere
	int listStart;
	int listEnd;
	DDA dda;
	
	//vec3 debugColour = vec3(0.0, 0.0, 0.0);
	//Track if a collision was made, if so no need to continue traversing grid
	bool hitSphere = false;
	if(initSphereListRay(rayOrigin, rayDirection, dda, listStart, listEnd)){
		while(getNextSphereList(dda, listStart, listEnd) && !hitSphere){
			//debugColour += vec3(0.1, 0.1, 0.1);
			for(int i=listStart; i<listEnd; i++){
				hitSphere = getSphereCollision(spheres[sphereLists[i]], rayOrigin, rayDirection, c) || hitSphere;
			}
		}
	}
	//Loop through each plane
	for(int i=0; i<planes.length(); i++){
		getPlaneCollision(planes[i], rayOrigin, rayDirection, c);
	}
	//No collisions just draw the sky
	if(!c.hit){
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
			lightDir = l.pos - c.hitAt;
		}
		float dist = length(lightDir);
		lightDir /= dist; //Normalize
		//For efficiency don't calculate effect of distant light sources
		//Also check for shadows here
		if((l.isDirectional>0.0 || dist < l.maxDist)) {
#if (NUM_SHADOW_RAYS <= 0)
			applyLighting(lightColour, lightDir, c.hitNorm, rayDirection, l, c.hitShininess, c.hitColour, dist, 1.0);
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
				applyLighting(lightColour, lightDir, c.hitNorm, rayDirection, l, c.hitShininess, c.hitColour, dist, frac);
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
						vec3 newDir = (l.pos + lightRight * x + lightUp * y) - c.hitAt;
						dist = length(newDir);
						newDir /= dist;
						if(!hasCollision(hitAt, newDir, BIAS, dist)){
							applyLighting(lightColour, newDir, c.hitNorm, rayDirection, l, c.hitShininess, c.hitColour, dist, NUM_SHADOW_RAYS * NUM_SHADOW_RAYS);
						}
						newDir = (l.pos - lightRight * x + lightUp * y) - c.hitAt;
						dist = length(newDir);
						newDir /= dist;
						if(!hasCollision(hitAt, newDir, BIAS, dist)){
							applyLighting(lightColour, newDir, c.hitNorm, rayDirection, l, c.hitShininess, c.hitColour, dist, NUM_SHADOW_RAYS * NUM_SHADOW_RAYS);
						}
						newDir = (l.pos + lightRight * x - lightUp * y) - c.hitAt;
						dist = length(newDir);
						newDir /= dist;
						if(!hasCollision(hitAt, newDir, BIAS, dist)){
							applyLighting(lightColour, newDir, c.hitNorm, rayDirection, l, c.hitShininess, c.hitColour, dist, NUM_SHADOW_RAYS * NUM_SHADOW_RAYS);
						}
						newDir = (l.pos - lightRight * x - lightUp * y) - c.hitAt;
						dist = length(newDir);
						newDir /= dist;
						if(!hasCollision(hitAt, newDir, BIAS, dist)){
							applyLighting(lightColour, newDir, c.hitNorm, rayDirection, l, c.hitShininess, c.hitColour, dist, NUM_SHADOW_RAYS * NUM_SHADOW_RAYS);
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
Reflections:
Cast primary ray:
If(NumReflections < MAX_DEPTH or Amount_Contributed > MIN_CONTR):
	colour += GetPixelColour(Reflection_Ray)

getPixelColour(Ray):
	fireRay(Ray


*/
