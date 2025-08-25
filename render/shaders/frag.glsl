#version 330

in vec3 texCoord;
in float ambientOcclusion;

uniform sampler2DArray tex;

void main(){
    gl_FragColor = texture(tex, texCoord) - vec4(vec3(ambientOcclusion), 0.0);
}
