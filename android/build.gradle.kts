allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Redirected outside the project (which lives under OneDrive-synced
// Desktop) to a local-only path. OneDrive's sync agent and Windows Defender
// were intermittently locking files mid-build inside build/, breaking
// Gradle's incremental clean/merge tasks with AccessDeniedException /
// "unable to delete directory" errors.
val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("C:/FlutterBuild/ScrollControl").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
