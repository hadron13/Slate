#version 330

layout (location = 0) in vec3 aPos;
layout (location = 1) in vec3 aTexCoord;
layout (location = 2) in float ao;

out vec3 texCoord;
out float ambientOcclusion;

uniform mat4 model;
uniform mat4 view;
uniform mat4 proj;

void main(){
    gl_Position = proj * view * model * vec4(aPos, 1.0);
    texCoord = aTexCoord;
    ambientOcclusion = ao;
}