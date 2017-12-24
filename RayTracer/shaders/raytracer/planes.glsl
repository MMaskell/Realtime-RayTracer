// P = rO + t(rD)
// 0 = N . (P - p0)
// 0 = N . (p0 - rO + t(rD))
// t = (p0 - rO).N / (rD.N)
// If rD.N = 0: Parallel (For this treat as no intersection)
// If t < 0: Behind ray origin
bool getPlaneCollision(Plane p, vec3 rayOrigin, vec3 rayDirection, inout Collision c){
	float rDN = dot(rayDirection, p.norm);
	//Check not zero (or very close to)
	if(abs(rDN)>0.0001 && dot(-rayDirection, p.norm) > 0.0) {
		float t = dot((p.pos - rayOrigin), p.norm) / rDN;
		if(t > 0.0 && t < c.dist){
			c.hit = true;
			c.dist = t;
			c.hitAt = rayOrigin + c.dist * rayDirection;
			c.hitNorm = p.norm;
			c.hitShininess = p.shininess;
			c.hitColour = p.colour;
			return true;
		}
	}
	return false;
}