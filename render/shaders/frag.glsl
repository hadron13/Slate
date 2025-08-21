#version 330

in vec3 texCoord;
in float ambientOcclusion;

uniform sampler2DArray tex;

void main(){
    gl_FragColor = texture(tex, texCoord) - vec4(vec3(max(ambientOcclusion-0.1, 0.0) * 0.2), 0.0);
}