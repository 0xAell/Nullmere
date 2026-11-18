"""Runs a model script of Art/blender dry, without Blender: the stand-ins
for Blender's bpy, bmesh and mathutils beside this file take the script's
calls, its meshes are kept, transformed and joined as Blender would, and
the scene is written out as JSON (each mesh's points in Blender's axes, its
faces and their materials) where Blender would write glTF.

What it is for: a script written or changed where Blender is not, checked
before the Models workflow makes it. It prints what finish_building prints,
each level's triangles far and near, and they are Blender's own (the
Granary's script, run here, counts what its committed model holds to the
triangle; `glbcount.py` counts a model made in Blender the same way). Its
meshes can be drawn in Chromium, every level side by side, the work's slot
ringed in red:

    python3 Tools/blender-dry-run/run.py Art/blender/granary.py build/granary.json
    python3 Tools/blender-dry-run/glbcount.py Art/models/granary.glb
    npm install --no-save --prefix Tools/blender-dry-run three@0.160.0
    node Tools/blender-dry-run/shoot.js build/granary.json build/granary.png "dist=1.7"

What it does not do: bevels add no corners (no work's script asks for
one), a bisect cuts nothing, and no glTF is written; the model the game
reads is still Blender's.
"""
import os
import runpy
import sys

here = os.path.dirname(os.path.abspath(__file__))
script = os.path.abspath(sys.argv[1])
sys.path[:0] = [here, os.path.dirname(script)]
import canonical  # the repository's, from the script's folder
canonical.rewrite = lambda path: None
sys.argv = [script] + sys.argv[2:]
runpy.run_path(script, run_name="__main__")
