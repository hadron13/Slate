#version 330

in vec3 texCoord;

uniform sampler2DArray tex;

void main(){
    gl_FragColor = texture(tex, texCoord);
}