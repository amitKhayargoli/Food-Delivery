

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir = File(rootProject.projectDir, "../build")
rootProject.layout.buildDirectory.value(rootProject.layout.projectDirectory.dir(newBuildDir.absolutePath))

subprojects {
    val newSubprojectBuildDir = File(rootProject.projectDir, "../build/${project.name}")
    project.layout.buildDirectory.value(project.layout.projectDirectory.dir(newSubprojectBuildDir.absolutePath))
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
