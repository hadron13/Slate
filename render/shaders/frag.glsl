#version 330

in vec2 texCoord;

uniform sampler2DArray tex;

void main(){
    gl_FragColor = texture(tex, vec3(texCoord, 0));
}