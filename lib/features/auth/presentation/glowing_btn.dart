import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:prenova/core/theme/app_pallete.dart';


class GlowingButton extends StatefulWidget {
  final String text;
  final VoidCallback onPressed;

  const GlowingButton({Key? key, required this.text, required this.onPressed}) : super(key: key);

  @override
  _GlowingButtonState createState() => _GlowingButtonState();
}

class _GlowingButtonState extends State<GlowingButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Color?> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  Widget build(BuildContext context) {
    return  ElevatedButton(
            onPressed: widget.onPressed,
            style: ElevatedButton.styleFrom(
              padding: EdgeInsets.symmetric(vertical: 16, horizontal: 32),
              backgroundColor: AppPallete.gradient1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              elevation: 0, // Remove default elevation
            ),
            child: Text(
              widget.text,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          );
  }
  

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
