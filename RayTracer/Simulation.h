#pragma once
#include <vector>
#include <string>
#include <glm\glm.hpp>
#include <glm\gtc\matrix_transform.hpp>
#include "Shader.h"
#include "Structures.h"

#define GROUP_SIZE 1

#define CAMERA_WIDTH 16.0f
#define CAMERA_HEIGHT 9.0f

#define FOV 90

extern GLFWwindow* window;

class Simulation {
public:
	Simulation();
	~Simulation();
	void init();
	void run(double dt);
	Shader shader;
	std::vector<std::string> args;
	double DENSITY = 1.0;
	int numSpheres = 10;
	int numLights = 1;
	int material = 0;
	bool autoCamera = false;
	std::string csv = "";
	int width = 1280;
	int height = 720;
private:
	double horizontalAngle = 3.1415926, verticalAngle = 0.0;
	bool firstMove = true;
	double ang = 0.0;
	float dist = 4.0f;
	glm::vec3 centre = glm::vec3(0.0f, 0.5f, 0.0f);
	glm::vec3 camPos;
	glm::mat4 camMat;
	GLuint camMatPos;
	void manualUpdateCamera(double dt);
	void autoUpdateCamera(double dt);
	void generateGrid(std::vector<Sphere>& spheres, std::vector<int>& grid, std::vector<int>& lists, GLuint id);
	std::vector<Sphere> spheres;
	std::vector<Plane> planes;
	std::vector<Light> lights;
	std::vector<Material> materials;
	std::vector<Triangle> triangles;
	std::vector<int> grid;
	std::vector<int> list;
	GLuint lightSSBO;
	float lightAng = 0;
};

